import Foundation
import NetworkExtension

// 网络包捕获管理器 (使用VPN模式)
class PacketCaptureManager {
    static let shared = PacketCaptureManager()

    private var isCapturing = false
    private var capturedPackets: [CapturedPacket] = []

    var onPacketCaptured: ((CapturedPacket) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    init() {
        capturedPackets = PacketStorage.shared.loadPackets()
        setupVPNCallbacks()
    }

    // 设置VPN回调
    private func setupVPNCallbacks() {
        // VPN状态变化
        VPNManager.shared.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                let isConnected = (status == .connected)
                self?.isCapturing = isConnected
                self?.onStatusChanged?(isConnected)
            }
        }

        // 新包到达
        VPNManager.shared.onPacketCaptured = { [weak self] packetDict in
            self?.processVPNPacket(packetDict)
        }
    }

    // 开始抓包
    func startCapture() {
        guard !isCapturing else { return }

        print("启动VPN抓包...")

        VPNManager.shared.startVPN { [weak self] success, error in
            if success {
                print("VPN启动成功，开始抓包")
                DispatchQueue.main.async {
                    self?.isCapturing = true
                    self?.onStatusChanged?(true)
                }
            } else {
                print("VPN启动失败: \(error ?? "未知错误")")
                DispatchQueue.main.async {
                    self?.onStatusChanged?(false)
                }
            }
        }
    }

    // 停止抓包
    func stopCapture() {
        guard isCapturing else { return }

        VPNManager.shared.stopVPN()
        isCapturing = false
        onStatusChanged?(false)

        // 保存抓取的包
        PacketStorage.shared.savePackets(capturedPackets)

        print("停止抓包，共抓取 \(capturedPackets.count) 个包")
    }

    // 处理VPN抓取的包
    private func processVPNPacket(_ packetDict: [String: Any]) {
        guard let id = packetDict["id"] as? String,
              let timestamp = packetDict["timestamp"] as? TimeInterval,
              let sourceIP = packetDict["sourceIP"] as? String,
              let destIP = packetDict["destinationIP"] as? String,
              let sourcePort = packetDict["sourcePort"] as? UInt16,
              let destPort = packetDict["destinationPort"] as? UInt16,
              let protocolStr = packetDict["protocol"] as? String,
              let dataBase64 = packetDict["data"] as? String,
              let data = Data(base64Encoded: dataBase64) else {
            return
        }

        // 转换协议类型
        let protocolType: PacketProtocol
        switch protocolStr {
        case "TCP": protocolType = .tcp
        case "UDP": protocolType = .udp
        default: protocolType = .unknown
        }

        // 创建包对象
        let packet = CapturedPacket(
            id: UUID(uuidString: id) ?? UUID(),
            timestamp: Date(timeIntervalSince1970: timestamp),
            sourceIP: sourceIP,
            destinationIP: destIP,
            sourcePort: sourcePort,
            destinationPort: destPort,
            protocolType: protocolType,
            data: data,
            processName: "System",
            requestURL: nil,
            headers: nil
        )

        // 添加到列表
        DispatchQueue.main.async { [weak self] in
            self?.capturedPackets.insert(packet, at: 0)

            // 限制最多保存1000个包
            if let count = self?.capturedPackets.count, count > 1000 {
                self?.capturedPackets = Array(self!.capturedPackets.prefix(1000))
            }

            self?.onPacketCaptured?(packet)
        }
    }

    // 获取所有抓取的包
    func getAllPackets() -> [CapturedPacket] {
        return capturedPackets
    }

    // 清除所有包
    func clearPackets() {
        capturedPackets.removeAll()
        PacketStorage.shared.savePackets([])
        VPNManager.shared.clearAllPackets()
    }
}
