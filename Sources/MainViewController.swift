import UIKit

class MainViewController: UIViewController {

    // UI组件
    private var tableView: UITableView!
    private var captureButton: UIButton!
    private var clearButton: UIButton!
    private var statusLabel: UILabel!
    private var segmentControl: UISegmentedControl!

    // 数据源
    private var packets: [CapturedPacket] = []
    private var tasks: [ReplayTask] = []
    private var isCapturing = false

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "抓包重放工具"
        view.backgroundColor = .systemBackground

        // 添加导出VPN配置按钮
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "安装VPN",
            style: .plain,
            target: self,
            action: #selector(installVPNProfile)
        )

        setupUI()
        setupManagers()
        loadData()
    }

    private func setupUI() {
        // 状态标签
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "就绪 (VPN模式)"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        view.addSubview(statusLabel)

        // 分段控制器
        segmentControl = UISegmentedControl(items: ["抓取的包", "定时任务"])
        segmentControl.translatesAutoresizingMaskIntoConstraints = false
        segmentControl.selectedSegmentIndex = 0
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        view.addSubview(segmentControl)

        // 表格视图
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PacketCell.self, forCellReuseIdentifier: "PacketCell")
        tableView.register(TaskCell.self, forCellReuseIdentifier: "TaskCell")
        view.addSubview(tableView)

        // 按钮容器
        let buttonStack = UIStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 10
        view.addSubview(buttonStack)

        // 抓包按钮
        captureButton = UIButton(type: .system)
        captureButton.setTitle("开始抓包", for: .normal)
        captureButton.backgroundColor = .systemGreen
        captureButton.setTitleColor(.white, for: .normal)
        captureButton.layer.cornerRadius = 8
        captureButton.addTarget(self, action: #selector(toggleCapture), for: .touchUpInside)
        buttonStack.addArrangedSubview(captureButton)

        // 清除按钮
        clearButton = UIButton(type: .system)
        clearButton.setTitle("清除", for: .normal)
        clearButton.backgroundColor = .systemRed
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.layer.cornerRadius = 8
        clearButton.addTarget(self, action: #selector(clearData), for: .touchUpInside)
        buttonStack.addArrangedSubview(clearButton)

        // 布局约束
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            segmentControl.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            segmentControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: segmentControl.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            buttonStack.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 10),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            buttonStack.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupManagers() {
        // 设置抓包回调
        PacketCaptureManager.shared.onPacketCaptured = { [weak self] packet in
            DispatchQueue.main.async {
                self?.packets.insert(packet, at: 0)
                if self?.segmentControl.selectedSegmentIndex == 0 {
                    self?.tableView.reloadData()
                }
                self?.statusLabel.text = "已抓取 \(self?.packets.count ?? 0) 个包"
            }
        }

        PacketCaptureManager.shared.onStatusChanged = { [weak self] capturing in
            DispatchQueue.main.async {
                self?.isCapturing = capturing
                self?.updateCaptureButton()
                self?.statusLabel.text = capturing ? "正在抓包... (VPN已连接)" : "就绪 (VPN模式)"
                self?.statusLabel.textColor = capturing ? .systemGreen : .secondaryLabel
            }
        }

        // 设置调度器回调
        SchedulerManager.shared.onTasksUpdated = { [weak self] tasks in
            DispatchQueue.main.async {
                self?.tasks = tasks
                if self?.segmentControl.selectedSegmentIndex == 1 {
                    self?.tableView.reloadData()
                }
            }
        }

        SchedulerManager.shared.onTaskExecuted = { [weak self] task, success, message in
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: success ? "重放成功" : "重放失败",
                    message: "\(task.packet.displayName)\n\(message ?? "")",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self?.present(alert, animated: true)
            }
        }

        // 启动定时任务
        SchedulerManager.shared.startAllScheduledTasks()
    }

    private func loadData() {
        packets = PacketCaptureManager.shared.getAllPackets()
        tasks = SchedulerManager.shared.getAllTasks()
        tableView.reloadData()
    }

    @objc private func toggleCapture() {
        if isCapturing {
            PacketCaptureManager.shared.stopCapture()
        } else {
            // 显示Loading提示
            let loadingAlert = UIAlertController(title: "请稍候", message: "正在启动VPN抓包...", preferredStyle: .alert)
            present(loadingAlert, animated: true)

            // 延迟一下让提示显示出来
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                PacketCaptureManager.shared.startCapture()

                // 3秒后关闭loading
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    loadingAlert.dismiss(animated: true) { [weak self] in
                        // 检查VPN状态
                        let status = VPNManager.shared.getCurrentStatus()
                        if status != .connected && status != .connecting {
                            // VPN启动可能失败，显示提示
                            let errorAlert = UIAlertController(
                                title: "需要授权",
                                message: "请在弹出的系统提示中点击\"允许\"以启用VPN抓包功能。\n\n如果没有看到提示，请到：\n设置 → 通用 → VPN与设备管理\n中查看VPN配置。",
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "我知道了", style: .default))
                            errorAlert.addAction(UIAlertAction(title: "打开设置", style: .default) { _ in
                                if let url = URL(string: "App-Prefs:root=General&path=ManagedConfigurationList") {
                                    UIApplication.shared.open(url)
                                }
                            })
                            self?.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        }
    }

    @objc private func clearData() {
        let alert = UIAlertController(title: "确认", message: "确定要清除所有数据吗？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确定", style: .destructive) { [weak self] _ in
            if self?.segmentControl.selectedSegmentIndex == 0 {
                PacketCaptureManager.shared.clearPackets()
                self?.packets.removeAll()
            } else {
                self?.tasks.forEach { SchedulerManager.shared.removeTask($0.id) }
                self?.tasks.removeAll()
            }
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    @objc private func segmentChanged() {
        tableView.reloadData()
        updateCaptureButton()
    }

    private func updateCaptureButton() {
        if segmentControl.selectedSegmentIndex == 0 {
            captureButton.isHidden = false
            captureButton.setTitle(isCapturing ? "停止抓包" : "开始抓包", for: .normal)
            captureButton.backgroundColor = isCapturing ? .systemOrange : .systemGreen
        } else {
            captureButton.isHidden = true
        }
    }

    @objc private func installVPNProfile() {
        let alert = UIAlertController(
            title: "安装VPN配置",
            message: "要使用VPN抓包功能，需要先安装VPN描述文件。\n\n点击\"安装\"后，系统会打开描述文件安装页面，请按提示完成安装。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "安装", style: .default) { [weak self] _ in
            self?.exportAndInstallVPNProfile()
        })

        present(alert, animated: true)
    }

    private func exportAndInstallVPNProfile() {
        // 从应用Bundle中读取mobileconfig文件
        guard let profilePath = Bundle.main.path(forResource: "PacketReplayVPN", ofType: "mobileconfig"),
              let profileData = try? Data(contentsOf: URL(fileURLPath: profilePath)) else {
            showError("无法找到VPN配置文件")
            return
        }

        // 保存到临时目录
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PacketReplayVPN.mobileconfig")
        do {
            try profileData.write(to: tempURL)

            // 使用UIActivityViewController分享/安装
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                if completed {
                    let successAlert = UIAlertController(
                        title: "下一步",
                        message: "描述文件已保存。\n\n请打开\"文件\"App，找到\"PacketReplayVPN.mobileconfig\"文件，点击安装。\n\n或者：\n设置 → 已下载描述文件 → 安装",
                        preferredStyle: .alert
                    )
                    successAlert.addAction(UIAlertAction(title: "好的", style: .default))
                    self?.present(successAlert, animated: true)
                }
            }

            present(activityVC, animated: true)

        } catch {
            showError("导出失败: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "错误", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showPacketDetail(_ packet: CapturedPacket) {
        let detailVC = PacketDetailViewController(packet: packet)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    private func scheduleReplay(_ packet: CapturedPacket) {
        let scheduleVC = ScheduleViewController(packet: packet)
        scheduleVC.onScheduled = { [weak self] task in
            SchedulerManager.shared.addTask(task)
            self?.segmentControl.selectedSegmentIndex = 1
            self?.segmentChanged()
        }
        navigationController?.pushViewController(scheduleVC, animated: true)
    }
}

// MARK: - UITableViewDelegate & DataSource
extension MainViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return segmentControl.selectedSegmentIndex == 0 ? packets.count : tasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentControl.selectedSegmentIndex == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "PacketCell", for: indexPath) as! PacketCell
            cell.configure(with: packets[indexPath.row])
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell", for: indexPath) as! TaskCell
            cell.configure(with: tasks[indexPath.row])
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if segmentControl.selectedSegmentIndex == 0 {
            showPacketDetail(packets[indexPath.row])
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if segmentControl.selectedSegmentIndex == 0 {
            let scheduleAction = UIContextualAction(style: .normal, title: "定时重放") { [weak self] _, _, completion in
                self?.scheduleReplay(self!.packets[indexPath.row])
                completion(true)
            }
            scheduleAction.backgroundColor = .systemBlue

            let replayAction = UIContextualAction(style: .normal, title: "立即重放") { [weak self] _, _, completion in
                guard let packet = self?.packets[indexPath.row] else { return }
                PacketReplayManager.shared.replayPacket(packet) { success, message in
                    DispatchQueue.main.async {
                        let alert = UIAlertController(
                            title: success ? "成功" : "失败",
                            message: message,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "确定", style: .default))
                        self?.present(alert, animated: true)
                    }
                }
                completion(true)
            }
            replayAction.backgroundColor = .systemGreen

            return UISwipeActionsConfiguration(actions: [replayAction, scheduleAction])
        } else {
            let deleteAction = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
                guard let task = self?.tasks[indexPath.row] else { return }
                SchedulerManager.shared.removeTask(task.id)
                completion(true)
            }

            return UISwipeActionsConfiguration(actions: [deleteAction])
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - 自定义Cell
class PacketCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let timeLabel = UILabel()
    private let protocolLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.font = .boldSystemFont(ofSize: 16)
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textColor = .tertiaryLabel
        protocolLabel.font = .systemFont(ofSize: 12)
        protocolLabel.textAlignment = .right

        [titleLabel, subtitleLabel, timeLabel, protocolLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: protocolLabel.leadingAnchor, constant: -10),

            protocolLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            protocolLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            protocolLabel.widthAnchor.constraint(equalToConstant: 60),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            timeLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 5),
            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(with packet: CapturedPacket) {
        titleLabel.text = packet.processName
        subtitleLabel.text = "\(packet.destinationIP):\(packet.destinationPort)"
        timeLabel.text = packet.dateString
        protocolLabel.text = packet.protocolType.rawValue
    }
}

class TaskCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let repeatLabel = UILabel()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.font = .boldSystemFont(ofSize: 16)
        timeLabel.font = .systemFont(ofSize: 14)
        timeLabel.textColor = .secondaryLabel
        repeatLabel.font = .systemFont(ofSize: 12)
        repeatLabel.textColor = .tertiaryLabel
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textAlignment = .right

        [titleLabel, timeLabel, repeatLabel, statusLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            statusLabel.widthAnchor.constraint(equalToConstant: 60),

            timeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            repeatLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 5),
            repeatLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            repeatLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(with task: ReplayTask) {
        titleLabel.text = task.packet.displayName
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        timeLabel.text = "执行时间: \(formatter.string(from: task.scheduledTime))"
        repeatLabel.text = "重复: \(task.repeatMode.rawValue)"
        statusLabel.text = task.isEnabled ? "✓ 启用" : "✗ 禁用"
        statusLabel.textColor = task.isEnabled ? .systemGreen : .systemRed
    }
}
