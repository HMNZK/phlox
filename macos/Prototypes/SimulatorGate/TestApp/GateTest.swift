import UIKit

@main
final class GateTest: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = TestScreen()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class TestScreen: UIViewController {
    private let label = UILabel()
    private let text = UITextField()
    private let moving = UIView()
    private var count = 0
    private var timer: Timer?
    private var frame = 0
    private var events: [[String: Any]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        label.frame = CGRect(x: 20, y: 90, width: 360, height: 60)
        label.text = "タップ: 0"
        view.addSubview(label)
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 20, y: 155, width: 360, height: 50)
        button.setTitle("タップを数える", for: .normal)
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)
        view.addSubview(button)
        let drag = UIView(frame: CGRect(x: 20, y: 230, width: 360, height: 100))
        drag.backgroundColor = .systemBlue
        drag.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
        view.addSubview(drag)
        text.frame = CGRect(x: 20, y: 350, width: 360, height: 60)
        text.borderStyle = .roundedRect
        text.placeholder = "物理キーの入力結果"
        text.autocorrectionType = .no
        text.autocapitalizationType = .none
        text.keyboardType = .asciiCapable
        text.addTarget(self, action: #selector(changed), for: .editingChanged)
        view.addSubview(text)
        moving.frame = CGRect(x: 20, y: 440, width: 60, height: 60)
        moving.backgroundColor = .red
        view.addSubview(moving)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        record(["起動": true, "幅": view.bounds.width, "高さ": view.bounds.height, "倍率": view.window?.screen.scale ?? UIScreen.main.scale])
    }

    private func animate() {
        frame += 1
        moving.frame.origin.x = 20 + CGFloat(frame % 150) * 2
        moving.backgroundColor = frame % 60 < 30 ? .red : .green
        if frame % 30 == 0 { record(["アニメーション": frame]) }
    }

    @objc private func tap() {
        count += 1
        label.text = "タップ: \(count)"
        record(["タップ": count])
    }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: view)
        label.text = "ドラッグ: \(Int(delta.x))"
        record(["ドラッグ状態": gesture.state.rawValue, "移動X": delta.x, "移動Y": delta.y])
    }
    @objc private func changed() { record(["文字": text.text ?? ""]) }
    @objc private func background() { record(["バックグラウンド": true]) }

    private func record(_ values: [String: Any]) {
        var values = values
        values["時刻"] = Date().timeIntervalSince1970
        events.append(values)
        do {
            let data = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            let url = URL.documentsDirectory.appendingPathComponent("events.json")
            try data.write(to: url, options: .atomic)
        } catch { print("観測結果の保存失敗: \(error)") }
    }
}
