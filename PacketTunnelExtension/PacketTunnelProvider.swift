import NetworkExtension
import Network

// Packet Tunnel Provider - 网络包隧道提供者
class PacketTunnelProvider: NEPacketTunnelProvider {

    private var connection: NWUDPSession?
    private var pendingStartCompletion: ((Error?) -> Void)?

    // 启动VPN隧道
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("PacketTunnel: 开始启动VPN隧道")

        // 配置网络设置
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // IPv4 设置 - 拦截所有流量
        let ipv4Settings = NEIPv4Settings(addresses: ["10.8.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        networkSettings.ipv4Settings = ipv4Settings

        // DNS 设置
        let dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
        networkSettings.dnsSettings = dnsSettings

        // MTU 设置
        networkSettings.mtu = 1500

        // 应用网络设置
        setTunnelNetworkSettings(networkSettings) { [weak self] error in
            if let error = error {
                NSLog("PacketTunnel: 设置网络失败: \(error)")
                completionHandler(error)
                return
            }

            NSLog("PacketTunnel: 网络设置成功，开始读取数据包")
            self?.startReadingPackets()
            completionHandler(nil)
        }
    }

    // 停止VPN隧道
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NSLog("PacketTunnel: 停止VPN隧道，原因: \(reason)")

        connection?.cancel()
        connection = nil

        completionHandler()
    }

    // 处理应用发来的消息
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        NSLog("PacketTunnel: 收到应用消息")

        // 可以在这里处理主应用发来的命令
        if let message = String(data: messageData, encoding: .utf8) {
            NSLog("PacketTunnel: 消息内容: \(message)")
        }

        completionHandler?(nil)
    }

    // 读取网络包
    private func startReadingPackets() {
        // 持续读取IP包
        packetFlow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }

            // 处理每个包
            for (index, packet) in packets.enumerated() {
                let protocolNumber = protocols[index].intValue
                self.processPacket(packet, protocolNumber: protocolNumber)
            }

            // 继续读取
            self.startReadingPackets()
        }
    }

    // 处理单个网络包
    private func processPacket(_ packetData: Data, protocolNumber: Int) {
        // 解析IP包
        guard packetData.count >= 20 else { return }

        let versionAndHeaderLength = packetData[0]
        let version = (versionAndHeaderLength >> 4) & 0x0F

        guard version == 4 else {
            // IPv6 或其他，直接转发
            writePacket(packetData, protocolNumber: protocolNumber)
            return
        }

        // 解析IPv4头部
        let headerLength = Int((versionAndHeaderLength & 0x0F)) * 4
        guard packetData.count >= headerLength else {
            writePacket(packetData, protocolNumber: protocolNumber)
            return
        }

        // 提取协议类型
        let ipProtocol = packetData[9]

        // 提取源IP和目标IP
        let sourceIP = extractIP(from: packetData, offset: 12)
        let destIP = extractIP(from: packetData, offset: 16)

        // 提取端口（如果是TCP/UDP）
        var sourcePort: UInt16 = 0
        var destPort: UInt16 = 0

        if ipProtocol == 6 || ipProtocol == 17 { // TCP or UDP
            if packetData.count >= headerLength + 4 {
                sourcePort = UInt16(packetData[headerLength]) << 8 | UInt16(packetData[headerLength + 1])
                destPort = UInt16(packetData[headerLength + 2]) << 8 | UInt16(packetData[headerLength + 3])
            }
        }

        // 保存抓取的包
        savePacket(
            data: packetData,
            sourceIP: sourceIP,
            destIP: destIP,
            sourcePort: sourcePort,
            destPort: destPort,
            protocolType: ipProtocol
        )

        // 转发包（让网络继续工作）
        writePacket(packetData, protocolNumber: protocolNumber)
    }

    // 提取IP地址
    private func extractIP(from data: Data, offset: Int) -> String {
        guard data.count >= offset + 4 else { return "0.0.0.0" }
        return "\(data[offset]).\(data[offset+1]).\(data[offset+2]).\(data[offset+3])"
    }

    // 保存抓取的包到共享存储
    private func savePacket(data: Data, sourceIP: String, destIP: String,
                           sourcePort: UInt16, destPort: UInt16, protocolType: UInt8) {

        // 使用App Groups共享数据
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.packet.replay"
        ) else {
            NSLog("PacketTunnel: 无法访问共享容器")
            return
        }

        let packetsFile = sharedURL.appendingPathComponent("captured_packets.json")

        // 创建包数据
        let packet: [String: Any] = [
            "id": UUID().uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "sourceIP": sourceIP,
            "destinationIP": destIP,
            "sourcePort": sourcePort,
            "destinationPort": destPort,
            "protocol": getProtocolName(protocolType),
            "data": data.base64EncodedString(),
            "size": data.count
        ]

        // 读取现有包
        var packets: [[String: Any]] = []
        if let existingData = try? Data(contentsOf: packetsFile),
           let existingPackets = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
            packets = existingPackets
        }

        // 添加新包（限制最多1000个）
        packets.insert(packet, at: 0)
        if packets.count > 1000 {
            packets = Array(packets.prefix(1000))
        }

        // 保存
        if let jsonData = try? JSONSerialization.data(withJSONObject: packets, options: []) {
            try? jsonData.write(to: packetsFile)

            // 通知主应用
            notifyMainApp()
        }
    }

    // 转发网络包
    private func writePacket(_ packetData: Data, protocolNumber: Int) {
        let protocolFamily = NSNumber(value: protocolNumber)
        packetFlow.writePackets([packetData], withProtocols: [protocolFamily])
    }

    // 获取协议名称
    private func getProtocolName(_ protocolNumber: UInt8) -> String {
        switch protocolNumber {
        case 6: return "TCP"
        case 17: return "UDP"
        case 1: return "ICMP"
        default: return "OTHER"
        }
    }

    // 通知主应用有新包
    private func notifyMainApp() {
        // 可以使用Darwin Notification或其他IPC机制
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.packet.replay.newPacket" as CFString),
            nil, nil, true
        )
    }
}
