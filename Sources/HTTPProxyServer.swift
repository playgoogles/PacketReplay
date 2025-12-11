import Foundation
import Network

// HTTP代理服务器
class HTTPProxyServer {
    static let shared = HTTPProxyServer()

    private var listener: NWListener?
    private var connections: [NWConnection] = []
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
            parameters.acceptLocalOnly = false // 允许局域网访问
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("代理服务器已启动在端口: \(self?.port ?? 0)")
                    self?.isRunning = true
                    DispatchQueue.main.async {
                        self?.onStatusChanged?(true)
                    }
                case .failed(let error):
                    print("代理服务器启动失败: \(error)")
                    self?.isRunning = false
                    DispatchQueue.main.async {
                        self?.onStatusChanged?(false)
                    }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener?.start(queue: queue)

        } catch {
            print("创建代理服务器失败: \(error)")
        }
    }

    // 停止代理服务器
    func stop() {
        guard isRunning else { return }

        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()

        isRunning = false
        onStatusChanged?(false)

        print("代理服务器已停止")
    }

    // 处理新连接
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)

        receiveRequest(from: connection)
    }

    // 接收HTTP请求
    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                // 解析HTTP请求
                self.parseAndCaptureRequest(data, from: connection)

                // 转发请求到目标服务器
                self.forwardRequest(data, from: connection)
            }

            if !isComplete {
                self.receiveRequest(from: connection)
            } else {
                connection.cancel()
                self.connections.removeAll { $0 === connection }
            }
        }
    }

    // 解析并捕获HTTP请求
    private func parseAndCaptureRequest(_ data: Data, from connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else { return }

        // 解析HTTP请求头
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 3 else { return }

        let method = components[0]
        let urlString = components[1]

        // 解析Host
        var host = ""
        var headers: [String: String] = [:]

        for line in lines.dropFirst() {
            if line.isEmpty { break }

            let parts = line.components(separatedBy: ": ")
            if parts.count >= 2 {
                let key = parts[0]
                let value = parts[1]
                headers[key] = value

                if key.lowercased() == "host" {
                    host = value
                }
            }
        }

        // 创建捕获的包
        let packet = CapturedPacket(
            id: UUID(),
            timestamp: Date(),
            sourceIP: "127.0.0.1",
            destinationIP: host,
            sourcePort: 0,
            destinationPort: 80,
            protocolType: urlString.hasPrefix("https://") ? .https : .http,
            data: data,
            processName: method,
            requestURL: urlString.hasPrefix("http") ? urlString : "http://\(host)\(urlString)",
            headers: headers
        )

        DispatchQueue.main.async { [weak self] in
            self?.onPacketCaptured?(packet)
        }

        print("捕获请求: \(method) \(urlString)")
    }

    // 转发请求到目标服务器
    private func forwardRequest(_ data: Data, from clientConnection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8),
              let firstLine = requestString.components(separatedBy: "\r\n").first else {
            return
        }

        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }

        let urlString = components[1]

        // 解析目标主机和端口
        var host = ""
        var port: UInt16 = 80

        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            if let url = URL(string: urlString) {
                host = url.host ?? ""
                port = UInt16(url.port ?? (url.scheme == "https" ? 443 : 80))
            }
        } else {
            // 从Host头获取
            let lines = requestString.components(separatedBy: "\r\n")
            for line in lines {
                if line.lowercased().hasPrefix("host:") {
                    let hostValue = line.components(separatedBy: ": ")[1]
                    if hostValue.contains(":") {
                        let parts = hostValue.components(separatedBy: ":")
                        host = parts[0]
                        port = UInt16(parts[1]) ?? 80
                    } else {
                        host = hostValue
                        port = 80
                    }
                    break
                }
            }
        }

        guard !host.isEmpty else { return }

        // 连接到目标服务器
        let targetHost = NWEndpoint.Host(host)
        let targetPort = NWEndpoint.Port(rawValue: port) ?? .http
        let targetConnection = NWConnection(host: targetHost, port: targetPort, using: .tcp)

        targetConnection.start(queue: queue)

        // 发送请求到目标服务器
        targetConnection.send(content: data, completion: .contentProcessed { _ in
            // 接收目标服务器的响应
            self.receiveResponse(from: targetConnection, to: clientConnection)
        })
    }

    // 接收目标服务器响应
    private func receiveResponse(from targetConnection: NWConnection, to clientConnection: NWConnection) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
            if let data = data, !data.isEmpty {
                // 转发响应给客户端
                clientConnection.send(content: data, completion: .contentProcessed { _ in })
            }

            if !isComplete {
                self.receiveResponse(from: targetConnection, to: clientConnection)
            } else {
                targetConnection.cancel()
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
                    if name == "en0" || name == "en1" { // WiFi或以太网
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
