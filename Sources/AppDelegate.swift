import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 创建窗口
        window = UIWindow(frame: UIScreen.main.bounds)

        // 创建主视图控制器
        let mainVC = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainVC)

        // 设置导航栏样式
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationController.navigationBar.standardAppearance = appearance
            navigationController.navigationBar.scrollEdgeAppearance = appearance
        }

        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        // 启动定时任务调度
        SchedulerManager.shared.startAllScheduledTasks()

        print("抓包重放工具已启动")

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // 应用即将进入后台
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 保存数据
        let packets = PacketCaptureManager.shared.getAllPackets()
        PacketStorage.shared.savePackets(packets)

        let tasks = SchedulerManager.shared.getAllTasks()
        PacketStorage.shared.saveTasks(tasks)

        print("数据已保存")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // 应用即将进入前台
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // 应用已激活
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // 应用即将终止
        PacketCaptureManager.shared.stopCapture()
        SchedulerManager.shared.stopAllTasks()
    }
}
