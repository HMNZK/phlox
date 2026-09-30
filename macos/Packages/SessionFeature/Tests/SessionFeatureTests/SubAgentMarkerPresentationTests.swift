import Testing
import SwiftUI
import AgentDomain
@testable import SessionFeature

@Suite("SubAgentMarkerPresentation")
struct SubAgentMarkerPresentationTests {
    @Test("実行中は状態の文字を出さず、完了・失敗は従来どおり出す")
    func statusLabelVisibility() {
        #expect(SubAgentMarkerPresentation.showsStatusLabel(for: .running) == false)
        #expect(SubAgentMarkerPresentation.showsStatusLabel(for: .completed))
        #expect(SubAgentMarkerPresentation.showsStatusLabel(for: .failed))
    }

    @Test("光は実行中だけ。視差効果を減らす設定では動かさない")
    func glowMode() {
        #expect(SubAgentMarkerPresentation.glow(for: .running, reduceMotion: false) == .comet)
        #expect(SubAgentMarkerPresentation.glow(for: .running, reduceMotion: true) == .staticHighlight)
        for status in [SubAgentStatus.completed, .failed] {
            #expect(SubAgentMarkerPresentation.glow(for: status, reduceMotion: false) == .none)
            #expect(SubAgentMarkerPresentation.glow(for: status, reduceMotion: true) == .none)
        }
    }

    @Test("光の先頭は左上（0）から一定の速さで進み、一周で戻る")
    func headPosition() {
        let perimeter = 1040.0
        let lap = perimeter / SubAgentMarkerPresentation.speed
        #expect(SubAgentMarkerPresentation.headPosition(time: 0, perimeter: perimeter) == 0)
        #expect(abs(SubAgentMarkerPresentation.headPosition(time: lap / 4, perimeter: perimeter) - 0.25) < 1e-9)
        #expect(abs(SubAgentMarkerPresentation.headPosition(time: lap * 3 + lap / 2, perimeter: perimeter) - 0.5) < 1e-9)
        #expect(SubAgentMarkerPresentation.headPosition(time: 5, perimeter: 0) == 0)
    }

    @Test("尾の区間は 0...1 に収まり、左上をまたぐと 2 つに分かれる")
    func trimRanges() {
        #expect(SubAgentMarkerPresentation.trimRanges(head: 0.5, length: 0.1) == [0.4...0.5])
        let wrapped = SubAgentMarkerPresentation.trimRanges(head: 0.03, length: 0.1)
        #expect(wrapped.count == 2)
        #expect(wrapped[0] == 0...0.03)
        #expect(abs(wrapped[1].lowerBound - 0.93) < 1e-9 && wrapped[1].upperBound == 1)
        #expect(SubAgentMarkerPresentation.trimRanges(head: 0.1, length: 0.1) == [0...0.1])
    }

    @Test("全周は矩形の周長から角の欠けを引いた値")
    func perimeter() {
        let square = SubAgentMarkerPresentation.perimeter(size: CGSize(width: 100, height: 100), cornerRadius: 0)
        #expect(square == 400)
        let round = SubAgentMarkerPresentation.perimeter(size: CGSize(width: 100, height: 50), cornerRadius: 8)
        #expect(abs(round - (300 - (8 - 2 * Double.pi) * 8)) < 1e-9)
    }

    @Test("極端に小さい・不正な枠でも周長・尾・先頭が有限で範囲内に収まる")
    func degenerateSizes() {
        let sizes = [CGSize.zero, CGSize(width: 1, height: 1), CGSize(width: -5, height: 10),
                     CGSize(width: 3, height: 200), CGSize(width: CGFloat.nan, height: 40), CGSize(width: 100, height: CGFloat.infinity)]
        for size in sizes {
            let perimeter = SubAgentMarkerPresentation.perimeter(size: size, cornerRadius: 8)
            #expect(perimeter.isFinite && perimeter >= 0)
            let tail = SubAgentMarkerPresentation.tailFraction(perimeter: perimeter)
            #expect(tail.isFinite && (0...1).contains(tail))
            let head = SubAgentMarkerPresentation.headPosition(time: 12.3, perimeter: perimeter)
            #expect(head.isFinite && (0...1).contains(head))
        }
        #expect(SubAgentMarkerPresentation.tailFraction(perimeter: 0) == 0)
        #expect(SubAgentMarkerPresentation.tailFraction(perimeter: 20) == 1)
        #expect(SubAgentMarkerPresentation.canDrawComet(perimeter: 0) == false)
        #expect(SubAgentMarkerPresentation.canDrawComet(perimeter: .nan) == false)
        #expect(SubAgentMarkerPresentation.canDrawComet(perimeter: 300))
    }

    @Test("不正な区間の入力は空、長さは一周までに収まる")
    func trimRangesGuards() {
        #expect(SubAgentMarkerPresentation.trimRanges(head: .nan, length: 0.1).isEmpty)
        #expect(SubAgentMarkerPresentation.trimRanges(head: 0.5, length: .infinity).isEmpty)
        #expect(SubAgentMarkerPresentation.trimRanges(head: 0.5, length: 0).isEmpty)
        for range in SubAgentMarkerPresentation.trimRanges(head: 0.5, length: 5) {
            #expect(range.lowerBound >= 0 && range.upperBound <= 1)
        }
    }

    @Test("枠・尾の path は小さい矩形でも NaN を含まず、通常サイズでは描かれる")
    func pathsAreFinite() {
        let rects = [CGRect.zero, CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 0.4, height: 30),
                     CGRect(x: 0, y: 0, width: 4, height: 300), CGRect(x: 0, y: 0, width: 480, height: 40)]
        for rect in rects {
            for path in [SubAgentMarkerOutline(cornerRadius: 8).path(in: rect),
                         SubAgentMarkerTrail(cornerRadius: 8, head: 0.02, length: 0.3).path(in: rect)] {
                let box = path.boundingRect
                let values = [box.origin.x, box.origin.y, box.width, box.height]
                #expect(values.allSatisfy { $0.isFinite || box.isNull })
            }
        }
        #expect(SubAgentMarkerOutline(cornerRadius: 8).path(in: .zero).isEmpty)
        #expect(!SubAgentMarkerOutline(cornerRadius: 8).path(in: CGRect(x: 0, y: 0, width: 480, height: 40)).isEmpty)
        #expect(!SubAgentMarkerTrail(cornerRadius: 8, head: 0.02, length: 0.3).path(in: CGRect(x: 0, y: 0, width: 480, height: 40)).isEmpty)
    }
}
