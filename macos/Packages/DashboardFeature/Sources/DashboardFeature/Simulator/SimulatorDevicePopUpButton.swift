import AppKit
import DesignSystem

/// ネイティブのメニューとキー操作を保ち、帯だけを見本の印・文字で描く。
final class SimulatorDevicePopUpButton: NSPopUpButton {
    var device: SimulatorDevice?
    var compact = false

    override var intrinsicContentSize: NSSize {
        let name = device?.name ?? "端末なし"
        let nameWidth = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11.5)]).width
        let runtimeWidth = compact || device == nil ? 0 : ((device?.runtimeLabel ?? "") as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width + 6
        return NSSize(width: ceil(nameWidth + runtimeWidth + 43), height: 22)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        needsDisplay = true
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(DSColor.textPrimary.opacity(0.08)).setFill()
        let face = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
        face.fill()
        if window?.firstResponder === self {
            NSColor(DSColor.accent).setStroke()
            face.lineWidth = 2
            face.stroke()
        }
        var x: CGFloat = 10
        if let device {
            Self.drawState(device, in: NSRect(x: x, y: bounds.midY - 3.5, width: 7, height: 7))
        } else {
            NSColor(DSColor.textSecondary).setStroke()
            let mark = NSBezierPath(ovalIn: NSRect(x: x, y: bounds.midY - 3.5, width: 7, height: 7))
            mark.lineWidth = 1.2
            mark.stroke()
        }
        x += 13
        let name = device?.name ?? "端末なし"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor(DSColor.textPrimary),
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        var nameAttributes = attributes
        nameAttributes[.paragraphStyle] = paragraph
        (name as NSString).draw(in: NSRect(x: x, y: bounds.midY - 7,
                                         width: max(0, bounds.width - x - 19), height: 16),
                               withAttributes: nameAttributes)
        x += (name as NSString).size(withAttributes: attributes).width + 6
        if !compact, let device {
            (device.runtimeLabel as NSString).draw(at: NSPoint(x: x, y: bounds.midY - 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(DSColor.textSecondary),
            ])
        }
        ("▾" as NSString).draw(at: NSPoint(x: bounds.maxX - 13, y: bounds.midY - 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor(DSColor.textSecondary),
        ])
    }

    static func stateImage(_ device: SimulatorDevice) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 12), flipped: false) { _ in
            drawState(device, in: NSRect(x: 1.5, y: 2.5, width: 7, height: 7))
            return true
        }
    }

    private static func drawState(_ device: SimulatorDevice, in rect: NSRect) {
        let mark = NSBezierPath(ovalIn: rect)
        NSColor(DSColor.textPrimary).setFill()
        NSColor(DSColor.textSecondary).setStroke()
        if device.isBooted { mark.fill() }
        else {
            mark.lineWidth = 1.2
            if device.state == "Booting" { mark.setLineDash([2, 2], count: 2, phase: 0) }
            mark.stroke()
        }
    }
}
