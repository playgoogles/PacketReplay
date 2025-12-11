import Foundation
import NetworkExtension

// VPN管理器 - 控制VPN连接进行网络包抓取
class VPNManager {
    static let shared = VPNManager()

    private var vpnManager: NETunnelProviderManager?
    private var isObserving = false

    var onStatusChanged: ((NEVPNStatus) -> Void)?
    var onPacketCaptured: (([String: Any]) -> Void)?

    init() {
        setupNotifications()
        loadVPNConfiguration()
    }

    // 设置通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange,
            object: nil
        )

        // 监听新包通知
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { (center, observer, name, object, userInfo) in
                guard let observer = observer else { return }
                let manager = Unmanaged<VPNManager>.fromOpaque(observer).takeUnretainedValue()
                manager.loadNewPackets()
            },
            "com.packet.replay.newPacket" as CFString,
            nil,
            .deliverImmediately
        )
    }

    // 加载VPN配置
    private func loadVPNConfiguration() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                print("VPN: 加载配置失败: \(error)")
                return
            }

            if let manager = managers?.first {
                self?.vpnManager = manager
                print("VPN: 已加载现有配置")
            } else {
                self?.createVPNConfiguration()
            }
        }
    }

    // 创建VPN配置
    private func createVPNConfiguration() {
        let manager = NETunnelProviderManager()

        // 配置协议
        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = "com.packet.replay.tunnel"
        protocolConfiguration.serverAddress = "PacketReplay"

        manager.protocolConfiguration = protocolConfiguration
        manager.localizedDescription = "抓包重放VPN"
        manager.isEnabled = true

        // 保存配置
        manager.saveToPreferences { [weak self] error in
            if let error = error {
                print("VPN: 保存配置失败: \(error)")
                return
            }

            print("VPN: 配置保存成功")
            self?.vpnManager = manager
            self?.loadVPNConfiguration()
        }
    }

    // 启动VPN连接
    func startVPN(completion: @escaping (Bool, String?) -> Void) {
        guard let manager = vpnManager else {
            completion(false, "VPN配置未就绪，请稍后重试")
            return
        }

        // 确保配置已启用
        if !manager.isEnabled {
            manager.isEnabled = true
            manager.saveToPreferences { [weak self] error in
                if let error = error {
                    completion(false, "保存配置失败: \(error.localizedDescription)")
                    return
                }
                self?.startVPN(completion: completion)
            }
            return
        }

        do {
            try manager.connection.startVPNTunnel()
            print("VPN: 已启动VPN隧道")
            completion(true, nil)
        } catch {
            print("VPN: 启动失败: \(error)")
            completion(false, "启动失败: \(error.localizedDescription)")
        }
    }

    // 停止VPN连接
    func stopVPN() {
        vpnManager?.connection.stopVPNTunnel()
        print("VPN: 已停止VPN隧道")
    }

    // VPN状态变化
    @objc private func vpnStatusDidChange(_ notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }

        print("VPN: 状态变化: \(statusString(connection.status))")
        onStatusChanged?(connection.status)
    }

    // 获取当前状态
    func getCurrentStatus() -> NEVPNStatus {
        return vpnManager?.connection.status ?? .invalid
    }

    // 状态字符串
    private func statusString(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "未配置"
        case .disconnected: return "已断开"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .reasserting: return "重新连接中..."
        case .disconnecting: return "断开中..."
        @unknown default: return "未知状态"
        }
    }

    // 从共享存储加载新包
    private func loadNewPackets() {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.packet.replay"
        ) else {
            return
        }

        let packetsFile = sharedURL.appendingPathComponent("captured_packets.json")

        guard let data = try? Data(contentsOf: packetsFile),
              let packets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        // 通知有新包
        for packet in packets {
            onPacketCaptured?(packet)
        }
    }

    // 获取所有抓取的包
    func getAllCapturedPackets() -> [[String: Any]] {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.packet.replay"
        ) else {
            return []
        }

        let packetsFile = sharedURL.appendingPathComponent("captured_packets.json")

        guard let data = try? Data(contentsOf: packetsFile),
              let packets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return packets
    }

    // 清除所有包
    func clearAllPackets() {
        guard let sharedURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.packet.replay"
        ) else {
            return
        }

        let packetsFile = sharedURL.appendingPathComponent("captured_packets.json")
        try? FileManager.default.removeItem(at: packetsFile)
    }
}
