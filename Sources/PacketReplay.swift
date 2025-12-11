import Foundation
import Network

// 数据包重放管理器
class PacketReplayManager {
    static let shared = PacketReplayManager()

    private let queue = DispatchQueue(label: "com.packet.replay")
    private var activeConnections: [UUID: NWConnection] = [:]

    var onReplayComplete: ((ReplayTask, Bool, String?) -> Void)?
    var onReplayProgress: ((String) -> Void)?

    // 立即重放指定的包
    func replayPacket(_ packet: CapturedPacket, completion: @escaping (Bool, String?) -> Void) {
        queue.async { [weak self] in
            self?.executeReplay(packet, completion: completion)
        }
    }

    // 执行重放
    private func executeReplay(_ packet: CapturedPacket, completion: @escaping (Bool, String?) -> Void) {
        print("开始重放包: \(packet.displayName)")
        onReplayProgress?("准备重放: \(packet.displayName)")

        switch packet.protocolType {
        case .http, .https:
            replayHTTPPacket(packet, completion: completion)
        case .tcp:
            replayTCPPacket(packet, completion: completion)
        case .udp:
            replayUDPPacket(packet, completion: completion)
        case .unknown:
            completion(false, "不支持的协议类型")
        }
    }

    // 重放HTTP/HTTPS请求
    private func replayHTTPPacket(_ packet: CapturedPacket, completion: @escaping (Bool, String?) -> Void) {
        guard let urlString = packet.requestURL,
              let url = URL(string: urlString) else {
            completion(false, "无效的URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = packet.data

        // 设置headers
        packet.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        onReplayProgress?("发送HTTP请求...")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("重放失败: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("重放成功，状态码: \(httpResponse.statusCode)")
                self?.onReplayProgress?("重放成功，状态码: \(httpResponse.statusCode)")
                completion(true, "状态码: \(httpResponse.statusCode)")
            } else {
                completion(true, "请求已发送")
            }
        }

        task.resume()
    }

    // 重放TCP包
    private func replayTCPPacket(_ packet: CapturedPacket, completion: @escaping (Bool, String?) -> Void) {
        let host = NWEndpoint.Host(packet.destinationIP)
        let port = NWEndpoint.Port(rawValue: packet.destinationPort) ?? .any

        let connection = NWConnection(host: host, port: port, using: .tcp)
        activeConnections[packet.id] = connection

        onReplayProgress?("建立TCP连接...")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("TCP连接已建立")
                self?.sendTCPData(connection, data: packet.data, packetId: packet.id, completion: completion)
            case .failed(let error):
                print("TCP连接失败: \(error)")
                self?.activeConnections.removeValue(forKey: packet.id)
                completion(false, "连接失败: \(error.localizedDescription)")
            case .cancelled:
                self?.activeConnections.removeValue(forKey: packet.id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func sendTCPData(_ connection: NWConnection, data: Data, packetId: UUID, completion: @escaping (Bool, String?) -> Void) {
        onReplayProgress?("发送TCP数据...")

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("发送数据失败: \(error)")
                completion(false, error.localizedDescription)
            } else {
                print("数据发送成功，共 \(data.count) 字节")
                self?.onReplayProgress?("发送成功: \(data.count) 字节")
                completion(true, "已发送 \(data.count) 字节")
            }

            connection.cancel()
            self?.activeConnections.removeValue(forKey: packetId)
        })
    }

    // 重放UDP包
    private func replayUDPPacket(_ packet: CapturedPacket, completion: @escaping (Bool, String?) -> Void) {
        let host = NWEndpoint.Host(packet.destinationIP)
        let port = NWEndpoint.Port(rawValue: packet.destinationPort) ?? .any

        let connection = NWConnection(host: host, port: port, using: .udp)
        activeConnections[packet.id] = connection

        onReplayProgress?("建立UDP连接...")

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("UDP连接已建立")
                self?.sendUDPData(connection, data: packet.data, packetId: packet.id, completion: completion)
            case .failed(let error):
                print("UDP连接失败: \(error)")
                self?.activeConnections.removeValue(forKey: packet.id)
                completion(false, "连接失败: \(error.localizedDescription)")
            case .cancelled:
                self?.activeConnections.removeValue(forKey: packet.id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func sendUDPData(_ connection: NWConnection, data: Data, packetId: UUID, completion: @escaping (Bool, String?) -> Void) {
        onReplayProgress?("发送UDP数据...")

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("发送数据失败: \(error)")
                completion(false, error.localizedDescription)
            } else {
                print("数据发送成功，共 \(data.count) 字节")
                self?.onReplayProgress?("发送成功: \(data.count) 字节")
                completion(true, "已发送 \(data.count) 字节")
            }

            connection.cancel()
            self?.activeConnections.removeValue(forKey: packetId)
        })
    }

    // 取消所有活动连接
    func cancelAllConnections() {
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
    }
}
