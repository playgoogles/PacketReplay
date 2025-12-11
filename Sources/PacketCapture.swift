import Foundation

// 网络包捕获管理器 (使用HTTP代理模式)
class PacketCaptureManager {
    static let shared = PacketCaptureManager()

    private var isCapturing = false
    private var capturedPackets: [CapturedPacket] = []

    var onPacketCaptured: ((CapturedPacket) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?

    init() {
        capturedPackets = PacketStorage.shared.loadPackets()
        setupProxyCallbacks()
    }

    // 设置代理服务器回调
    private func setupProxyCallbacks() {
        // 代理服务器状态变化
        HTTPProxyServer.shared.onStatusChanged = { [weak self] isRunning in
            DispatchQueue.main.async {
                self?.isCapturing = isRunning
                self?.onStatusChanged?(isRunning)
            }
        }

        // 新包到达
        HTTPProxyServer.shared.onPacketCaptured = { [weak self] packet in
            self?.processPacket(packet)
        }
    }

    // 开始抓包
    func startCapture() {
        guard !isCapturing else { return }

        print("启动HTTP代理抓包...")
        HTTPProxyServer.shared.start()
    }

    // 停止抓包
    func stopCapture() {
        guard isCapturing else { return }

        HTTPProxyServer.shared.stop()
        isCapturing = false
        onStatusChanged?(false)

        // 保存抓取的包
        PacketStorage.shared.savePackets(capturedPackets)

        print("停止抓包，共抓取 \(capturedPackets.count) 个包")
    }

    // 处理捕获的包
    private func processPacket(_ packet: CapturedPacket) {
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
    }

    // 获取代理配置信息
    func getProxyConfiguration() -> (host: String, port: UInt16) {
        let host = HTTPProxyServer.shared.getLocalIPAddress() ?? "127.0.0.1"
        return (host, 8888)
    }
}
