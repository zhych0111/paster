import AppKit

enum ScreenshotSelfTests {
    static func run() {
        let gate = ManualScrollGate()
        precondition(gate.mode == .automatic)
        precondition(gate.takeOver())
        precondition(gate.mode == .manual)
        precondition(!gate.takeOver())
        gate.stop()
        precondition(gate.mode == .stopped)

        let stitcher = FrameStitcher()
        let first = fixture(startRow: 0)
        let second = fixture(startRow: 80)
        guard case .started = stitcher.append(first) else { preconditionFailure("Missing initial frame") }
        guard case .noMovement = stitcher.append(first) else { preconditionFailure("Identical frame moved") }
        guard case .added(let rows) = stitcher.append(second), abs(rows - 80) <= 3 else {
            preconditionFailure("Overlapping frame was not stitched")
        }
        precondition(stitcher.image?.height == 240 + rows)
        let expected = NSBitmapImageRep(cgImage: fixture(startRow: 0, height: 320))
        let actual = NSBitmapImageRep(cgImage: stitcher.image!)
        for y in [0, 20, 100, 200, 300, 319] {
            for x in [0, 40, 100, 159] {
                let lhs = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let rhs = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                precondition(abs(lhs.redComponent - rhs.redComponent) < 0.02,
                             "Stitched pixels differ at \(x), \(y)")
            }
        }
        precondition(stitcher.png() != nil)
        let toolbarStitcher = FrameStitcher()
        _ = toolbarStitcher.append(fixture(startRow: 0, fixedTop: 20, fixedBottom: 16))
        guard case .added = toolbarStitcher.append(fixture(startRow: 80, fixedTop: 20, fixedBottom: 16)),
              let toolbarImage = toolbarStitcher.image,
              toolbarImage.height < 310, toolbarImage.height > 265 else {
            preconditionFailure("Fixed toolbars were not removed before stitching")
        }
        let pins = PinnedImageManager()
        var limitMessage: String?
        pins.onError = { limitMessage = $0 }
        let tiny = NSBitmapImageRep(cgImage: fixture(startRow: 0)).representation(using: .png, properties: [:])!
        for _ in 0..<10 { pins.add(tiny, show: false) }
        precondition(pins.count == 10)
        pins.add(tiny, show: false)
        precondition(pins.count == 10 && limitMessage != nil)
        pins.closeAll()
        precondition(pins.count == 0)
        print("Screenshot self-test: mode takeover, overlap, fixed toolbars, no movement, pin limit and cleanup passed")
    }

    private static func fixture(startRow: Int, height: Int = 240,
                                fixedTop: Int = 0, fixedBottom: Int = 0) -> CGImage {
        let width = 160
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let contentRow = startRow + y - fixedTop
                let value: UInt8
                if y < fixedTop { value = 50 }
                else if y >= height - fixedBottom { value = 200 }
                else { value = UInt8(truncatingIfNeeded: contentRow * 73 + x * 19 + (x * contentRow) % 37) }
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
            }
        }
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}
