import UIKit

// This host proves that Xcode can embed the helper and its framework. It has
// no pairing file, no guest executable and no JIT activation path.
@main
final class TKJITFixtureHost: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let controller = UIViewController()
        let label = UILabel(frame: controller.view.bounds)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "StikJIT build fixture only. JIT and game launch are disabled."
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(label)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        return true
    }
}
