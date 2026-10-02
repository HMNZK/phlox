import Foundation
import Testing
@testable import SimulatorBridgeKit

struct SimulatorInputMapperTests {
    @Test(arguments: SimulatorOrientation.allCases)
    func 画面内で始めた接触は余白で移動や解放しても端へ寄せる(orientation: SimulatorOrientation) {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 400)
        for size in [CGSize(width: 200, height: 400), CGSize(width: 400, height: 200)] {
            for rotated in [true, false] {
                let rect = SimulatorInputMapper.displayRect(in: bounds, pixelSize: size)!
                for point in [CGPoint(x: rect.minX - 1, y: rect.midY),
                              CGPoint(x: rect.maxX + 1, y: rect.midY),
                              CGPoint(x: rect.midX, y: rect.minY - 1),
                              CGPoint(x: rect.midX, y: rect.maxY + 1),
                              CGPoint(x: rect.minX - 10, y: rect.maxY + 10)] {
                    let edge = CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                                       y: min(max(point.y, rect.minY), rect.maxY))
                    #expect(SimulatorInputMapper.normalizedPoint(point, in: bounds, pixelSize: size,
                        orientation: orientation, surfaceIsRotated: rotated) == nil)
                    #expect(SimulatorInputMapper.normalizedPoint(point, in: bounds, pixelSize: size,
                        orientation: orientation, surfaceIsRotated: rotated, continuingTouch: true)
                        == SimulatorInputMapper.normalizedPoint(edge, in: bounds, pixelSize: size,
                            orientation: orientation, surfaceIsRotated: rotated))
                }
                #expect(SimulatorInputMapper.normalizedPoint(CGPoint(x: CGFloat.infinity, y: 0),
                    in: bounds, pixelSize: size, orientation: orientation,
                    surfaceIsRotated: rotated, continuingTouch: true) == nil)
            }
        }
    }
    @Test func 余白と上下反転() {
        let bounds = CGRect(x: 10, y: 20, width: 400, height: 400)
        let size = CGSize(width: 200, height: 400)
        #expect(SimulatorInputMapper.displayRect(in: bounds, pixelSize: size)
                == CGRect(x: 110, y: 20, width: 200, height: 400))
        #expect(map(CGPoint(x: 110, y: 420), bounds: bounds, size: size) == CGPoint(x: 0, y: 0))
        #expect(map(CGPoint(x: 310, y: 20), bounds: bounds, size: size) == CGPoint(x: 1, y: 1))
        #expect(map(CGPoint(x: 160, y: 320), bounds: bounds, size: size) == CGPoint(x: 0.25, y: 0.25))
        #expect(map(CGPoint(x: 109, y: 220), bounds: bounds, size: size) == nil)
        #expect(map(CGPoint(x: 311, y: 220), bounds: bounds, size: size) == nil)
    }

    @Test func 横画面の上下余白() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let size = CGSize(width: 400, height: 200)
        #expect(SimulatorInputMapper.displayRect(in: bounds, pixelSize: size)
                == CGRect(x: 0, y: 100, width: 400, height: 200))
        #expect(map(CGPoint(x: 200, y: 99), bounds: bounds, size: size) == nil)
        #expect(map(CGPoint(x: 200, y: 301), bounds: bounds, size: size) == nil)
    }

    @Test(arguments: SimulatorOrientation.allCases)
    func 回転済み画面の四隅(orientation: SimulatorOrientation) {
        let corners = [CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100),
                       CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let expected: [CGPoint]
        switch orientation {
        case .portrait:
            expected = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)]
        case .portraitUpsideDown:
            expected = [CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        case .landscapeLeft:
            expected = [CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1)]
        case .landscapeRight:
            expected = [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)]
        }
        for (point, result) in zip(corners, expected) {
            #expect(SimulatorInputMapper.normalizedPoint(
                point, in: CGRect(x: 0, y: 0, width: 100, height: 100),
                pixelSize: CGSize(width: 300, height: 300), orientation: orientation, surfaceIsRotated: true
            ) == result)
        }
    }

    @Test(arguments: SimulatorOrientation.allCases)
    func 未回転画面には回転を重ねない(orientation: SimulatorOrientation) {
        #expect(SimulatorInputMapper.normalizedPoint(
            CGPoint(x: 25, y: 75), in: CGRect(x: 0, y: 0, width: 100, height: 100),
            pixelSize: CGSize(width: 300, height: 300), orientation: orientation, surfaceIsRotated: false
        ) == CGPoint(x: 0.25, y: 0.25))
    }

    @Test func 不正な寸法と座標を送らない() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        for size in [CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: CGFloat.infinity, height: 100)] {
            #expect(SimulatorInputMapper.displayRect(in: bounds, pixelSize: size) == nil)
        }
        #expect(map(CGPoint(x: CGFloat.nan, y: 0), bounds: bounds, size: CGSize(width: 100, height: 100)) == nil)
        #expect(SimulatorInputMapper.displayRect(in: .zero, pixelSize: CGSize(width: 100, height: 100)) == nil)
    }

    private func map(_ point: CGPoint, bounds: CGRect, size: CGSize) -> CGPoint? {
        SimulatorInputMapper.normalizedPoint(point, in: bounds, pixelSize: size,
                                             orientation: .portrait, surfaceIsRotated: false)
    }
}
