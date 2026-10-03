import UIKit

@main
final class InputObserver: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = ObservedWindow(frame: UIScreen.main.bounds)
        let screen = InputScreen()
        window.recordTouch = { [weak screen] in screen?.record($0) }
        window.rootViewController = screen
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class InputScreen: UIViewController, UIScrollViewDelegate {
    private let text = ObservedTextField()
    private var events: [[String: Any]] = []
    private var count = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 20, y: 130, width: 300, height: 60)
        button.setTitle("タップを数える", for: .normal)
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)
        view.addSubview(button)
        let drag = ObservedTouchView(frame: CGRect(x: 20, y: 220, width: 300, height: 80))
        drag.backgroundColor = .systemBlue
        drag.recordTouch = { [weak self] in self?.record($0) }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan))
        pan.cancelsTouchesInView = false
        drag.addGestureRecognizer(pan)
        view.addSubview(drag)
        let scroll = UIScrollView(frame: CGRect(x: 20, y: 320, width: 300, height: 100))
        scroll.contentSize = CGSize(width: 300, height: 1000)
        scroll.backgroundColor = .systemYellow
        scroll.delegate = self
        view.addSubview(scroll)
        text.frame = CGRect(x: 20, y: 450, width: 300, height: 50)
        text.borderStyle = .roundedRect
        text.placeholder = "物理キー・貼り付け"
        text.autocorrectionType = .no
        text.autocapitalizationType = .none
        text.keyboardType = .asciiCapable
        text.recordPress = { [weak self] in self?.record($0) }
        text.addTarget(self, action: #selector(changed), for: .editingChanged)
        view.addSubview(text)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        record(["起動": true, "幅": view.bounds.width, "高さ": view.bounds.height, "倍率": UIScreen.main.scale])
    }

    @objc private func tap() { count += 1; record(["タップ": count]) }
    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: view)
        record(["ドラッグ状態": gesture.state.rawValue, "移動X": delta.x, "移動Y": delta.y])
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { record(["スクロール": scrollView.contentOffset.y]) }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        record(["スクロール終了速度X": velocity.x, "スクロール終了速度Y": velocity.y])
    }
    @objc private func changed() { record(["文字": text.text ?? ""]) }
    @objc private func background() { record(["バックグラウンド": true]) }

    fileprivate func record(_ values: [String: Any]) {
        var values = values
        values["時刻"] = Date().timeIntervalSince1970
        events.append(values)
        do {
            let data = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL.documentsDirectory.appendingPathComponent("events.json"), options: .atomic)
        } catch { print("観測結果の保存失敗: \(error)") }
    }
}

final class ObservedWindow: UIWindow {
    var recordTouch: (([String: Any]) -> Void)?

    override func sendEvent(_ event: UIEvent) {
        for touch in event.allTouches ?? [] {
            let point = touch.location(in: self)
            recordTouch?(["全接触状態": touch.phase.rawValue, "全接触X": point.x, "全接触Y": point.y])
        }
        super.sendEvent(event)
    }
}

final class ObservedTextField: UITextField {
    var recordPress: (([String: Any]) -> Void)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        record(presses, state: "押下")
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        record(presses, state: "解放")
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        record(presses, state: "取消")
        super.pressesCancelled(presses, with: event)
    }

    private func record(_ presses: Set<UIPress>, state: String) {
        for press in presses {
            guard let key = press.key else { continue }
            recordPress?(["キー状態": state, "HIDコード": key.keyCode.rawValue,
                          "修飾キー": key.modifierFlags.rawValue, "キー文字": key.characters])
        }
    }
}

final class ObservedTouchView: UIView {
    var recordTouch: (([String: Any]) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        record(touches, state: "押下")
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        record(touches, state: "解放")
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        record(touches, state: "取消")
        super.touchesCancelled(touches, with: event)
    }

    private func record(_ touches: Set<UITouch>, state: String) {
        for touch in touches {
            let point = touch.location(in: superview)
            recordTouch?(["接触状態": state, "接触X": point.x, "接触Y": point.y])
        }
    }
}
