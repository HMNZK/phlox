import SwiftUI
import Testing
@testable import DesignSystemIOS

@Suite("開閉本文の高さ") @MainActor
struct DSDisclosureContentTests {
    @Test("開閉の途中でも横幅は変えず高さだけを補間する")
    func interpolationPreservesWidth() {
        for (expansion, height) in [(CGFloat(0), CGFloat(0)), (0.5, 40), (1, 80)] {
            let size = renderedSize(
                DSDisclosureHeightLayout(expansion: expansion) {
                    Color.red.frame(width: 120, height: 80)
                }
            )
            #expect(size.width == 120)
            #expect(size.height == height)
        }
    }

    @Test("開閉の自然な終点を保ち、Reduce Motionでは高さをアニメーションしない")
    func naturalEndpointsAndReducedMotionPolicy() {
        #expect(DSMotion.disclosureAnimation(reduceMotion: true) == nil)
        #expect(DSMotion.disclosureAnimation(reduceMotion: false) == DSMotion.disclosure)
        for expanded in [false, true] {
            let size = renderedSize(
                DSDisclosureContent(isExpanded: expanded) {
                    Color.red.frame(width: 120, height: 80)
                }
                .frame(width: 120)
            )
            #expect(size.width == 120)
            #expect(size.height == (expanded ? 80 : 0))
        }
    }

    private func renderedSize(_ view: some View) -> CGSize {
        let renderer = ImageRenderer(content: view)
        var size = CGSize.zero
        renderer.render { renderedSize, _ in size = renderedSize }
        return size
    }

    @Test("複数の本文を欠落させず全体の高さで開閉する")
    func multipleChildrenPreserveFullContentHeight() {
        for expanded in [false, true] {
            let size = renderedSize(
                DSDisclosureContent(isExpanded: expanded) {
                    Color.red.frame(width: 120, height: 40)
                    Color.blue.frame(width: 120, height: 30)
                }
                .frame(width: 120)
            )
            #expect(size.width == 120)
            #expect(size.height == (expanded ? 70 : 0))
        }
    }

    @Test("接続円弧は0.9秒で一周しReduce Motionでは静止する")
    func connectionSpinnerPeriodAndReducedMotion() {
        for (time, degrees) in [(0.0, 0.0), (0.225, 90), (0.45, 180), (0.675, 270), (0.9, 0)] {
            #expect(abs(DSMotion.spinnerRotation(at: time, reduceMotion: false) - degrees) < 0.000001)
            #expect(DSMotion.spinnerRotation(at: time, reduceMotion: true) == 0)
        }
        #expect(abs(DSMotion.spinnerRotation(at: 0.3, reduceMotion: false)
            - DSMotion.spinnerRotation(at: 1.2, reduceMotion: false)) < 0.000001)
    }

    @Test("閉じた本文は初期化時も描画時も構築せず開いた時だけ構築する")
    func collapsedContentIsNotBuilt() {
        let counter = DisclosureBuildCounter()
        let closed = DSDisclosureContent(isExpanded: false) {
            counter.makeContent()
        }
        #expect(counter.count == 0)
        #expect(renderedSize(closed.frame(width: 120)).height == 0)
        #expect(counter.count == 0)

        let open = DSDisclosureContent(isExpanded: true) {
            counter.makeContent()
        }
        #expect(counter.count == 0)
        #expect(renderedSize(open.frame(width: 120)).height == 80)
        #expect(counter.count > 0)
    }
}

@MainActor
private final class DisclosureBuildCounter {
    var count = 0

    func makeContent() -> some View {
        count += 1
        return Color.red.frame(width: 120, height: 80)
    }
}
