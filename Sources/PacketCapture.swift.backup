import Foundation
import Network

// 网络包捕获管理器
class PacketCaptureManager {
    static let shared = PacketCaptureManager()

    private var isCapturing = false
    private var capturedPackets: [CapturedPacket] = []
    private var listeners: [NWListener] = []
    private let queue = DispatchQueue(label: "com.packet.capture")

    var onPacketCaptured: ((CapturedPacket) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    init() {
        capturedPackets = PacketStorage.shared.loadPackets()
    }

    // 开始抓包
    func startCapture() {
        guard !isCapturing else { return }

        isCapturing = true
        onStatusChanged?(true)

        // 启动网络监听
        setupNetworkMonitoring()

        print("开始抓包...")
    }

    // 停止抓包
    func stopCapture() {
        guard isCapturing else { return }

        isCapturing = false
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        onStatusChanged?(false)

        // 保存抓取的包
        PacketStorage.shared.savePackets(capturedPackets)

        print("停止抓包，共抓取 \(capturedPackets.count) 个包")
    }

    // 获取所有抓取的包
    func getAllPackets() -> [CapturedPacket] {
        return capturedPackets
    }

    // 清除所有包
    func clearPackets() {
        capturedPackets.removeAll()
        PacketStorage.shared.savePackets([])
    }

    // 设置网络监听（使用URLProtocol拦截）
    private func setupNetworkMonitoring() {
        // 注册自定义URLProtocol来拦截HTTP/HTTPS请求
        URLProtocol.registerClass(PacketInterceptor.self)

        // 同时监听底层socket连接（用于非HTTP流量）
        monitorRawSockets()
    }

    // 监听原始socket
    private func monitorRawSockets() {
        // 监听TCP连接
        do {
            let tcpListener = try NWListener(using: .tcp)
            tcpListener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    print("TCP监听已就绪")
                }
            }
            tcpListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            tcpListener.start(queue: queue)
            listeners.append(tcpListener)
        } catch {
            print("启动TCP监听失败: \(error)")
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self,
                  let data = data,
                  let endpoint = connection.currentPath?.remoteEndpoint else {
                return
            }

            // 解析包信息
            self.processRawPacket(data: data, endpoint: endpoint, connection: connection)
        }
    }

    private func processRawPacket(data: Data, endpoint: NWEndpoint, connection: NWConnection) {
        guard isCapturing else { return }

        var destIP = ""
        var destPort: UInt16 = 0

        if case .hostPort(let host, let port) = endpoint {
            destIP = "\(host)"
            destPort = port.rawValue
        }

        let packet = CapturedPacket(
            id: UUID(),
            timestamp: Date(),
            sourceIP: "0.0.0.0",
            destinationIP: destIP,
            sourcePort: 0,
            destinationPort: destPort,
            protocolType: .tcp,
            data: data,
            processName: getProcessName(),
            requestURL: nil,
            headers: nil
        )

        queue.async { [weak self] in
            self?.capturedPackets.append(packet)
            self?.onPacketCaptured?(packet)
        }
    }

    private func getProcessName() -> String {
        return ProcessInfo.processInfo.processName
    }
}

// URLProtocol拦截器，用于捕获HTTP/HTTPS请求
class PacketInterceptor: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool {
        // 避免重复拦截
        guard URLProtocol.property(forKey: "PacketInterceptor", in: request) == nil else {
            return false
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }

        URLProtocol.setProperty(true, forKey: "PacketInterceptor", in: mutableRequest)

        // 捕获请求信息
        captureRequest(request)

        // 继续执行原始请求
        let task = URLSession.shared.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
                return
            }

            if let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            }

            if let data = data {
                self.client?.urlProtocol(self, didLoad: data)
            }

            self.client?.urlProtocolDidFinishLoading(self)
        }

        task.resume()
    }

    override func stopLoading() {
        // 清理资源
    }

    private func captureRequest(_ request: URLRequest) {
        guard let url = request.url else { return }

        var headers: [String: String] = [:]
        request.allHTTPHeaderFields?.forEach { headers[$0.key] = $0.value }

        let packet = CapturedPacket(
            id: UUID(),
            timestamp: Date(),
            sourceIP: "localhost",
            destinationIP: url.host ?? "",
            sourcePort: 0,
            destinationPort: UInt16(url.port ?? (url.scheme == "https" ? 443 : 80)),
            protocolType: url.scheme == "https" ? .https : .http,
            data: request.httpBody ?? Data(),
            processName: ProcessInfo.processInfo.processName,
            requestURL: url.absoluteString,
            headers: headers
        )

        PacketCaptureManager.shared.onPacketCaptured?(packet)
    }
}
