import UIKit

// 包详情视图控制器
class PacketDetailViewController: UIViewController {

    private let packet: CapturedPacket
    private var textView: UITextView!

    init(packet: CapturedPacket) {
        self.packet = packet
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "包详情"
        view.backgroundColor = .systemBackground

        setupUI()
        displayPacketInfo()
    }

    private func setupUI() {
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 添加工具栏按钮
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "复制", style: .plain, target: self, action: #selector(copyData)),
            UIBarButtonItem(title: "重放", style: .plain, target: self, action: #selector(replayPacket))
        ]
    }

    private func displayPacketInfo() {
        var info = ""

        info += "=== 基本信息 ===\n"
        info += "时间: \(packet.timestamp)\n"
        info += "进程: \(packet.processName)\n"
        info += "协议: \(packet.protocolType.rawValue)\n\n"

        info += "=== 网络信息 ===\n"
        info += "源地址: \(packet.sourceIP):\(packet.sourcePort)\n"
        info += "目标地址: \(packet.destinationIP):\(packet.destinationPort)\n\n"

        if let url = packet.requestURL {
            info += "=== 请求URL ===\n"
            info += "\(url)\n\n"
        }

        if let headers = packet.headers, !headers.isEmpty {
            info += "=== HTTP Headers ===\n"
            headers.forEach { key, value in
                info += "\(key): \(value)\n"
            }
            info += "\n"
        }

        info += "=== 数据内容 ===\n"
        info += "大小: \(packet.data.count) 字节\n\n"

        // 尝试显示为字符串
        if let string = String(data: packet.data, encoding: .utf8) {
            info += "文本内容:\n\(string)\n\n"
        }

        // 显示十六进制
        info += "十六进制:\n"
        let hexString = packet.data.map { String(format: "%02x", $0) }.joined(separator: " ")
        info += hexString

        textView.text = info
    }

    @objc private func copyData() {
        UIPasteboard.general.string = textView.text
        let alert = UIAlertController(title: "已复制", message: "包详情已复制到剪贴板", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    @objc private func replayPacket() {
        let alert = UIAlertController(title: "确认", message: "确定要重放这个包吗？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重放", style: .default) { [weak self] _ in
            guard let self = self else { return }

            PacketReplayManager.shared.replayPacket(self.packet) { success, message in
                DispatchQueue.main.async {
                    let resultAlert = UIAlertController(
                        title: success ? "重放成功" : "重放失败",
                        message: message,
                        preferredStyle: .alert
                    )
                    resultAlert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(resultAlert, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }
}

// 定时调度视图控制器
class ScheduleViewController: UIViewController {

    private let packet: CapturedPacket
    private var datePicker: UIDatePicker!
    private var repeatControl: UISegmentedControl!
    private var scheduleButton: UIButton!

    var onScheduled: ((ReplayTask) -> Void)?

    init(packet: CapturedPacket) {
        self.packet = packet
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "定时重放"
        view.backgroundColor = .systemBackground

        setupUI()
    }

    private func setupUI() {
        // 包信息标签
        let infoLabel = UILabel()
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.text = "包: \(packet.displayName)"
        infoLabel.font = .boldSystemFont(ofSize: 16)
        infoLabel.textAlignment = .center
        infoLabel.numberOfLines = 0
        view.addSubview(infoLabel)

        // 时间选择器
        let timeLabel = UILabel()
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.text = "执行时间"
        timeLabel.font = .systemFont(ofSize: 14)
        view.addSubview(timeLabel)

        datePicker = UIDatePicker()
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.minimumDate = Date()
        view.addSubview(datePicker)

        // 重复模式
        let repeatLabel = UILabel()
        repeatLabel.translatesAutoresizingMaskIntoConstraints = false
        repeatLabel.text = "重复模式"
        repeatLabel.font = .systemFont(ofSize: 14)
        view.addSubview(repeatLabel)

        repeatControl = UISegmentedControl(items: ["仅一次", "每小时", "每天"])
        repeatControl.translatesAutoresizingMaskIntoConstraints = false
        repeatControl.selectedSegmentIndex = 0
        view.addSubview(repeatControl)

        // 调度按钮
        scheduleButton = UIButton(type: .system)
        scheduleButton.translatesAutoresizingMaskIntoConstraints = false
        scheduleButton.setTitle("设置定时重放", for: .normal)
        scheduleButton.backgroundColor = .systemBlue
        scheduleButton.setTitleColor(.white, for: .normal)
        scheduleButton.layer.cornerRadius = 8
        scheduleButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        scheduleButton.addTarget(self, action: #selector(scheduleTask), for: .touchUpInside)
        view.addSubview(scheduleButton)

        // 布局
        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            timeLabel.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 30),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            datePicker.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 10),
            datePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            repeatLabel.topAnchor.constraint(equalTo: datePicker.bottomAnchor, constant: 20),
            repeatLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            repeatControl.topAnchor.constraint(equalTo: repeatLabel.bottomAnchor, constant: 10),
            repeatControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            repeatControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scheduleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            scheduleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scheduleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scheduleButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func scheduleTask() {
        let repeatMode: RepeatMode
        switch repeatControl.selectedSegmentIndex {
        case 0: repeatMode = .once
        case 1: repeatMode = .hourly
        case 2: repeatMode = .daily
        default: repeatMode = .once
        }

        let task = ReplayTask(
            packet: packet,
            scheduledTime: datePicker.date,
            repeatMode: repeatMode
        )

        onScheduled?(task)

        let alert = UIAlertController(
            title: "已设置",
            message: "定时重放任务已添加",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}
