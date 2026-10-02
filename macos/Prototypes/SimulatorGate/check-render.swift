import AppKit
import Foundation

// スクリーンショットの色付きアニメーション矩形を画素から検出する。
let root = URL(fileURLWithPath: CommandLine.arguments[1])
var observations: [[String: Any]] = []
for second in [2, 3, 6, 7, 10, 11] {
    let url = root.appendingPathComponent(String(format: "host-%02d.png", second))
    guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
        fatalError("表示画像を読み込めません: \(url.path)")
    }
    var minimumX = bitmap.pixelsWide
    var maximumX = -1
    var red = 0
    var green = 0
    for y in 1000..<min(1160, bitmap.pixelsHigh) {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let isRed = color.redComponent > 0.75 && color.greenComponent < 0.4 && color.blueComponent < 0.4
            let isGreen = color.greenComponent > 0.6 && color.redComponent < 0.7 && color.blueComponent < 0.4
            if isRed || isGreen {
                minimumX = min(minimumX, x)
                maximumX = max(maximumX, x)
                red += isRed ? 1 : 0
                green += isGreen ? 1 : 0
            }
        }
    }
    observations.append(["秒": second, "左端X": minimumX, "右端X": maximumX, "赤画素": red, "緑画素": green])
}
let result = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
try result.write(to: root.appendingPathComponent("render.json"))
print(String(decoding: result, as: UTF8.self))
