import Foundation
import UserNotifications

// 定时任务调度管理器
class SchedulerManager {
    static let shared = SchedulerManager()

    private var tasks: [ReplayTask] = []
    private var timers: [UUID: Timer] = [:]
    private let queue = DispatchQueue(label: "com.packet.scheduler")

    var onTaskExecuted: ((ReplayTask, Bool, String?) -> Void)?
    var onTasksUpdated: (([ReplayTask]) -> Void)?

    init() {
        tasks = PacketStorage.shared.loadTasks()
        requestNotificationPermission()
    }

    // 请求通知权限
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("通知权限已授予")
            } else if let error = error {
                print("通知权限请求失败: \(error)")
            }
        }
    }

    // 添加重放任务
    func addTask(_ task: ReplayTask) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.tasks.append(task)
            self.saveTasks()
            self.scheduleTask(task)

            DispatchQueue.main.async {
                self.onTasksUpdated?(self.tasks)
            }

            print("已添加任务: \(task.packet.displayName) 将在 \(task.scheduledTime) 执行")
        }
    }

    // 删除任务
    func removeTask(_ taskId: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let timer = self.timers[taskId] {
                timer.invalidate()
                self.timers.removeValue(forKey: taskId)
            }

            self.tasks.removeAll { $0.id == taskId }
            self.saveTasks()

            DispatchQueue.main.async {
                self.onTasksUpdated?(self.tasks)
            }
        }
    }

    // 更新任务
    func updateTask(_ task: ReplayTask) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                // 取消旧的定时器
                if let timer = self.timers[task.id] {
                    timer.invalidate()
                    self.timers.removeValue(forKey: task.id)
                }

                self.tasks[index] = task
                self.saveTasks()

                // 重新调度
                if task.isEnabled {
                    self.scheduleTask(task)
                }

                DispatchQueue.main.async {
                    self.onTasksUpdated?(self.tasks)
                }
            }
        }
    }

    // 获取所有任务
    func getAllTasks() -> [ReplayTask] {
        return tasks
    }

    // 调度任务
    private func scheduleTask(_ task: ReplayTask) {
        guard task.isEnabled else { return }

        let now = Date()
        var fireDate = task.scheduledTime

        // 如果时间已过，根据重复模式计算下次执行时间
        if fireDate < now {
            switch task.repeatMode {
            case .once:
                print("任务 \(task.packet.displayName) 时间已过，不会执行")
                return
            case .daily:
                while fireDate < now {
                    fireDate = Calendar.current.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
                }
            case .hourly:
                while fireDate < now {
                    fireDate = Calendar.current.date(byAdding: .hour, value: 1, to: fireDate) ?? fireDate
                }
            }
        }

        let timeInterval = fireDate.timeIntervalSince(now)

        // 创建定时器
        DispatchQueue.main.async { [weak self] in
            let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
                self?.executeTask(task)
            }

            self?.timers[task.id] = timer
            print("任务已调度: \(task.packet.displayName) 将在 \(fireDate) 执行（\(Int(timeInterval))秒后）")
        }

        // 设置通知
        scheduleNotification(for: task, at: fireDate)
    }

    // 执行任务
    private func executeTask(_ task: ReplayTask) {
        print("执行任务: \(task.packet.displayName)")

        PacketReplayManager.shared.replayPacket(task.packet) { [weak self] success, message in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.onTaskExecuted?(task, success, message)

                // 显示本地通知
                self.showNotification(
                    title: success ? "重放成功" : "重放失败",
                    body: "\(task.packet.displayName)\n\(message ?? "")"
                )

                // 处理重复任务
                if success && task.repeatMode != .once {
                    var nextTask = task
                    switch task.repeatMode {
                    case .daily:
                        nextTask.scheduledTime = Calendar.current.date(byAdding: .day, value: 1, to: task.scheduledTime) ?? task.scheduledTime
                    case .hourly:
                        nextTask.scheduledTime = Calendar.current.date(byAdding: .hour, value: 1, to: task.scheduledTime) ?? task.scheduledTime
                    case .once:
                        break
                    }

                    if nextTask.scheduledTime != task.scheduledTime {
                        self.updateTask(nextTask)
                    }
                } else if task.repeatMode == .once {
                    // 一次性任务执行后移除
                    self.removeTask(task.id)
                }
            }
        }
    }

    // 设置通知
    private func scheduleNotification(for task: ReplayTask, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "即将执行重放"
        content.body = task.packet.displayName
        content.sound = .default

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("添加通知失败: \(error)")
            }
        }
    }

    // 显示通知
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    // 启动所有已调度的任务
    func startAllScheduledTasks() {
        queue.async { [weak self] in
            guard let self = self else { return }

            for task in self.tasks where task.isEnabled {
                self.scheduleTask(task)
            }

            print("已启动 \(self.tasks.filter { $0.isEnabled }.count) 个定时任务")
        }
    }

    // 停止所有任务
    func stopAllTasks() {
        queue.async { [weak self] in
            self?.timers.values.forEach { $0.invalidate() }
            self?.timers.removeAll()
            print("已停止所有定时任务")
        }
    }

    private func saveTasks() {
        PacketStorage.shared.saveTasks(tasks)
    }
}
