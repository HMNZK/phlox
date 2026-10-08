import Foundation
import IOSurface
import Testing
@testable import SimulatorBridgeKit

struct SimulatorDisplayOrientationTests {
    @Test func スクロールを縦向き端末の軸へ変換する() {
        let cases: [(SimulatorOrientation, Double, Double)] = [
            (.portrait, 10, 20), (.portraitUpsideDown, -10, -20),
            (.landscapeLeft, -20, 10), (.landscapeRight, 20, -10)
        ]
        for (orientation, expectedX, expectedY) in cases {
            let delta = orientation.inputDelta(dx: 10, dy: 20)
            #expect(delta.dx == expectedX)
            #expect(delta.dy == expectedY)
        }
    }
    @Test func 時計回りに四方向を一周する() {
        #expect(SimulatorOrientation.portrait.clockwise == .landscapeRight)
        #expect(SimulatorOrientation.landscapeRight.clockwise == .portraitUpsideDown)
        #expect(SimulatorOrientation.portraitUpsideDown.clockwise == .landscapeLeft)
        #expect(SimulatorOrientation.landscapeLeft.clockwise == .portrait)
    }

    @Test(arguments: SimulatorOrientation.allCases)
    func 縦surfaceを表示の向きへ回し横寸法を入れ替える(orientation: SimulatorOrientation) throws {
        let info = try makeInfo(orientation: orientation, rotated: false)
        let expected = orientation.isLandscape ? CGSize(width: 800, height: 400) : CGSize(width: 400, height: 800)
        #expect(info.displayPixelSize == expected)
        let rotation: CGFloat = switch orientation {
        case .portrait: 0
        case .portraitUpsideDown: .pi
        case .landscapeLeft: .pi / 2
        case .landscapeRight: -.pi / 2
        }
        #expect(info.displayRotation == rotation)
        let rect = try #require(SimulatorInputMapper.displayRect(in: CGRect(x: 0, y: 0, width: 800, height: 800),
                                                               pixelSize: info.displayPixelSize))
        let topLeft: CGPoint = switch orientation {
        case .portrait: CGPoint(x: 0, y: 0)
        case .portraitUpsideDown: CGPoint(x: 1, y: 1)
        case .landscapeLeft: CGPoint(x: 1, y: 0)
        case .landscapeRight: CGPoint(x: 0, y: 1)
        }
        #expect(SimulatorInputMapper.normalizedPoint(CGPoint(x: rect.minX, y: rect.maxY),
                                                     in: CGRect(x: 0, y: 0, width: 800, height: 800),
                                                     pixelSize: info.displayPixelSize,
                                                     orientation: orientation, surfaceIsRotated: true) == topLeft)
    }

    @Test(arguments: SimulatorOrientation.allCases)
    func 回転済みsurfaceは二度回さない(orientation: SimulatorOrientation) throws {
        let info = try makeInfo(orientation: orientation, rotated: true)
        #expect(info.displayPixelSize == CGSize(width: 400, height: 800))
        #expect(info.displayRotation == 0)
    }

    private func makeInfo(orientation: SimulatorOrientation, rotated: Bool) throws -> SimulatorDisplayInfo {
        let surface = try #require(IOSurface(properties: [.width: 400, .height: 800, .bytesPerElement: 4]))
        return SimulatorDisplayInfo(udid: "orientation-test", connectionGeneration: 1, displayGeneration: 1,
                                    surface: surface, pixelWidth: 400, pixelHeight: 800,
                                    orientation: orientation, surfaceIsRotated: rotated, pixelFormat: 0)
    }
}
