import Foundation
import Network

// HTTP代理服务器 - 简化版
class HTTPProxyServer {
    static let shared = HTTPProxyServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.packet.replay.proxy")
    private let port: UInt16 = 8888

    var isRunning = false
    var onPacketCaptured: ((CapturedPacket) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    // 启动代理服务器
    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.acceptLocalOnly = false
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("✅ 代理服务器已启动在端口: \(self?.port ?? 0)")
                    self?.isRunning = true
                    DispatchQueue.main.async {
                        self?.onStatusChanged?(true)
                    }
                case .failed(let error):
                    print("❌ 代理服务器启动失败: \(error)")
                    self?.isRunning = false
                    DispatchQueue.main.async {
                        self?.onStatusChanged?(false)
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                print("📱 新连接: \(connection)")
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)

        } catch {
            print("❌ 创建代理服务器失败: \(error)")
        }
    }

    // 停止代理服务器
    func stop() {
        guard isRunning else { return }

        listener?.cancel()
        listener = nil

        isRunning = false
        onStatusChanged?(false)

        print("⏹️ 代理服务器已停止")
    }

    // 处理连接
    private func handleConnection(_ clientConnection: NWConnection) {
        clientConnection.start(queue: queue)

        // 读取客户端请求
        readRequest(from: clientConnection)
    }

    // 读取HTTP请求
    private func readRequest(from clientConnection: NWConnection) {
        clientConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                if isComplete || error != nil {
                    clientConnection.cancel()
                }
                return
            }

            print("📥 收到请求: \(data.count) 字节")

            // 解析请求
            if let requestString = String(data: data, encoding: .utf8) {
                print("📝 请求内容:\n\(requestString.prefix(200))")

                // 捕获请求
                self.captureRequest(data, requestString: requestString)

                // 转发请求
                self.forwardRequest(data, requestString: requestString, to: clientConnection)
            } else {
                print("⚠️ 无法解析请求")
                clientConnection.cancel()
            }
        }
    }

    // 捕获HTTP请求
    private func captureRequest(_ data: Data, requestString: String) {
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 3 else { return }

        let method = components[0]
        let urlPath = components[1]

        // 解析Host
        var host = ""
        var headers: [String: String] = [:]

        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex])
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value

                if key.lowercased() == "host" {
                    host = value
                }
            }
        }

        let packet = CapturedPacket(
            id: UUID(),
            timestamp: Date(),
            sourceIP: "127.0.0.1",
            destinationIP: host,
            sourcePort: 0,
            destinationPort: 80,
            protocolType: .http,
            data: data,
            processName: method,
            requestURL: "http://\(host)\(urlPath)",
            headers: headers
        )

        DispatchQueue.main.async { [weak self] in
            self?.onPacketCaptured?(packet)
        }
    }

    // 转发请求到目标服务器
    private func forwardRequest(_ data: Data, requestString: String, to clientConnection: NWConnection) {
        // 解析目标主机
        let lines = requestString.components(separatedBy: "\r\n")

        var targetHost = ""
        var targetPort: UInt16 = 80

        // 从Host头获取目标
        for line in lines {
            if line.lowercased().hasPrefix("host:") {
                let hostValue = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if hostValue.contains(":") {
                    let parts = hostValue.split(separator: ":")
                    targetHost = String(parts[0])
                    targetPort = UInt16(parts[1]) ?? 80
                } else {
                    targetHost = hostValue
                    targetPort = 80
                }
                break
            }
        }

        guard !targetHost.isEmpty else {
            print("❌ 无法解析目标主机")
            clientConnection.cancel()
            return
        }

        print("🎯 转发到: \(targetHost):\(targetPort)")

        // 连接到目标服务器
        let host = NWEndpoint.Host(targetHost)
        let port = NWEndpoint.Port(rawValue: targetPort)!
        let serverConnection = NWConnection(host: host, port: port, using: .tcp)

        serverConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("✅ 已连接到目标服务器")
                // 发送请求到目标服务器
                serverConnection.send(content: data, completion: .contentProcessed { error in
                    if let error = error {
                        print("❌ 发送失败: \(error)")
                        clientConnection.cancel()
                        serverConnection.cancel()
                    } else {
                        print("📤 请求已发送")
                        // 开始转发响应
                        self.forwardResponse(from: serverConnection, to: clientConnection)
                    }
                })
            case .failed(let error):
                print("❌ 连接目标服务器失败: \(error)")
                clientConnection.cancel()
            default:
                break
            }
        }

        serverConnection.start(queue: queue)
    }

    // 转发服务器响应到客户端
    private func forwardResponse(from serverConnection: NWConnection, to clientConnection: NWConnection) {
        serverConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                print("📦 收到响应: \(data.count) 字节")
                // 转发给客户端
                clientConnection.send(content: data, completion: .contentProcessed { _ in })

                // 继续读取
                if !isComplete {
                    self.forwardResponse(from: serverConnection, to: clientConnection)
                }
            }

            if isComplete || error != nil {
                print("✅ 响应传输完成")
                serverConnection.cancel()
                clientConnection.cancel()
            }
        }
    }

    // 获取本机IP地址
    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }

                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family

                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }

        return address ?? "127.0.0.1"
    }
}
