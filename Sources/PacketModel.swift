import Foundation

// 数据包模型
struct CapturedPacket: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let sourceIP: String
    let destinationIP: String
    let sourcePort: UInt16
    let destinationPort: UInt16
    let protocol: PacketProtocol
    let data: Data
    let processName: String
    let requestURL: String?
    let headers: [String: String]?

    var displayName: String {
        "\(processName) - \(destinationIP):\(destinationPort)"
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

enum PacketProtocol: String, Codable {
    case tcp = "TCP"
    case udp = "UDP"
    case http = "HTTP"
    case https = "HTTPS"
    case unknown = "Unknown"
}

// 重放任务
struct ReplayTask: Codable, Identifiable {
    let id: UUID
    var packet: CapturedPacket
    var scheduledTime: Date
    var isEnabled: Bool
    var repeatMode: RepeatMode

    init(packet: CapturedPacket, scheduledTime: Date, repeatMode: RepeatMode = .once) {
        self.id = UUID()
        self.packet = packet
        self.scheduledTime = scheduledTime
        self.isEnabled = true
        self.repeatMode = repeatMode
    }
}

enum RepeatMode: String, Codable {
    case once = "仅一次"
    case daily = "每天"
    case hourly = "每小时"
}

// 存储管理
class PacketStorage {
    static let shared = PacketStorage()

    private let packetsKey = "capturedPackets"
    private let tasksKey = "replayTasks"

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func savePackets(_ packets: [CapturedPacket]) {
        let url = documentsURL.appendingPathComponent("packets.json")
        if let data = try? JSONEncoder().encode(packets) {
            try? data.write(to: url)
        }
    }

    func loadPackets() -> [CapturedPacket] {
        let url = documentsURL.appendingPathComponent("packets.json")
        guard let data = try? Data(contentsOf: url),
              let packets = try? JSONDecoder().decode([CapturedPacket].self, from: data) else {
            return []
        }
        return packets
    }

    func saveTasks(_ tasks: [ReplayTask]) {
        let url = documentsURL.appendingPathComponent("tasks.json")
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: url)
        }
    }

    func loadTasks() -> [ReplayTask] {
        let url = documentsURL.appendingPathComponent("tasks.json")
        guard let data = try? Data(contentsOf: url),
              let tasks = try? JSONDecoder().decode([ReplayTask].self, from: data) else {
            return []
        }
        return tasks
    }
}
