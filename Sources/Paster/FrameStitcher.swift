import AppKit
import CoreGraphics

enum StitchResult {
    case started
    case added(Int)
    case noMovement
    case unreliable
    case pixelLimit
}

final class FrameStitcher {
    private(set) var image: CGImage?
    private var previous: CGImage?
    private let maximumPixels = 25_000_000
    private var calibratedBands = false
    private var fixedTop = 0
    private var fixedBottom = 0

    func append(_ frame: CGImage) -> StitchResult {
        guard frame.width * frame.height <= maximumPixels else { return .pixelLimit }
        if let previous, !calibratedBands,
           let old = grayscale(previous), let new = grayscale(frame),
           old.width == new.width, old.height == new.height {
            let difference = meanDifference(old.bytes, new.bytes, width: old.width,
                                            oldStart: 0, newStart: 0, rows: old.height)
            if difference >= 2.5 {
                calibratedBands = true
                let bands = detectFixedBands(old: old, new: new, originalHeight: frame.height)
                fixedTop = bands.top
                fixedBottom = bands.bottom
                if fixedTop + fixedBottom > 0,
                   let cropped = crop(previous) {
                    self.previous = cropped
                    image = cropped
                }
            }
        }
        guard let prepared = crop(frame) else { return .unreliable }
        return appendPrepared(prepared)
    }

    private func appendPrepared(_ frame: CGImage) -> StitchResult {
        guard let previous, let assembled = image else {
            image = frame
            previous = frame
            return .started
        }
        guard previous.width == frame.width, previous.height == frame.height,
              let old = grayscale(previous), let new = grayscale(frame) else { return .unreliable }
        let height = old.height
        let width = old.width
        let direct = meanDifference(old.bytes, new.bytes, width: width,
                                    oldStart: 0, newStart: 0, rows: height)
        if direct < 2.5 { return .noMovement }

        var bestShift = 0
        var best = Double.infinity
        var second = Double.infinity
        for shift in 4...max(4, Int(Double(height) * 0.78)) {
            let overlap = height - shift
            let margin = max(2, height / 18)
            guard overlap > margin * 2 else { continue }
            let score = meanDifference(old.bytes, new.bytes, width: width,
                                       oldStart: shift + margin, newStart: margin,
                                       rows: overlap - margin * 2)
            if score < best { second = best; best = score; bestShift = shift }
            else if score < second { second = score }
        }
        guard bestShift > 0, best < 18, best + 0.3 < second else { return .unreliable }
        let addedRows = Int((Double(bestShift) / Double(height) * Double(frame.height)).rounded())
        guard addedRows > 0 else { return .noMovement }
        let newHeight = assembled.height + addedRows
        guard frame.width * newHeight <= maximumPixels else { return .pixelLimit }
        guard let tail = frame.cropping(to: CGRect(x: 0, y: frame.height - addedRows,
                                                  width: frame.width, height: addedRows)),
              let context = CGContext(data: nil, width: frame.width, height: newHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .unreliable }
        context.draw(assembled, in: CGRect(x: 0, y: addedRows, width: frame.width,
                                           height: assembled.height))
        context.draw(tail, in: CGRect(x: 0, y: 0, width: frame.width, height: addedRows))
        guard let merged = context.makeImage() else { return .unreliable }
        image = merged
        self.previous = frame
        return .added(addedRows)
    }

    private func crop(_ frame: CGImage) -> CGImage? {
        if fixedTop + fixedBottom == 0 { return frame }
        guard frame.height > fixedTop + fixedBottom + 80 else { return nil }
        return frame.cropping(to: CGRect(x: 0, y: fixedTop, width: frame.width,
                                         height: frame.height - fixedTop - fixedBottom))
    }

    private func detectFixedBands(old: (bytes: [UInt8], width: Int, height: Int),
                                  new: (bytes: [UInt8], width: Int, height: Int),
                                  originalHeight: Int) -> (top: Int, bottom: Int) {
        let maximumRows = old.height / 5
        func rowIsFixed(_ row: Int) -> Bool {
            meanDifference(old.bytes, new.bytes, width: old.width,
                           oldStart: row, newStart: row, rows: 1) < 2.5
        }
        var top = 0
        while top < maximumRows && rowIsFixed(top) { top += 1 }
        var bottom = 0
        while bottom < maximumRows && rowIsFixed(old.height - 1 - bottom) { bottom += 1 }
        let topPixels = top >= 5 ? Int(Double(top) / Double(old.height) * Double(originalHeight)) : 0
        let bottomPixels = bottom >= 5 ? Int(Double(bottom) / Double(old.height) * Double(originalHeight)) : 0
        return (topPixels, bottomPixels)
    }

    func png() -> Data? {
        guard let image else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private func grayscale(_ image: CGImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        let width = 96
        let height = max(32, min(320, Int(Double(image.height) * 96 / Double(image.width))))
        var bytes = [UInt8](repeating: 0, count: width * height)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return success ? (bytes, width, height) : nil
    }

    private func meanDifference(_ old: [UInt8], _ new: [UInt8], width: Int,
                                oldStart: Int, newStart: Int, rows: Int) -> Double {
        var total = 0
        let sampleStep = 2
        for row in 0..<rows {
            let oldOffset = (oldStart + row) * width
            let newOffset = (newStart + row) * width
            for col in stride(from: 0, to: width, by: sampleStep) {
                total += abs(Int(old[oldOffset + col]) - Int(new[newOffset + col]))
            }
        }
        return Double(total) / Double(rows * (width / sampleStep))
    }
}
