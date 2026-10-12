import AppKit
import ScreenCaptureKit
import CoreImage
import CoreMedia

final class ScrollingFrameSource: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "Paster.ScrollingFrames", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var active = false
    private var cancelled = false
    var onFrame: ((CGImage) -> Void)?
    var onError: ((String) -> Void)?

    func start(screen: NSScreen, region: NSRect, completion: @escaping (Result<Void, Error>) -> Void) {
        cancelled = false
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            completion(.failure(NSError(domain: "Paster", code: 3,
                                        userInfo: [NSLocalizedDescriptionKey: "需要在系统设置中允许屏幕录制"])))
            return
        }
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            completion(.failure(NSError(domain: "Paster", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "无法识别显示器"])))
            return
        }
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                    throw NSError(domain: "Paster", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "显示器已经变化"])
                }
                let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: region.minX - screen.frame.minX,
                                           y: screen.frame.maxY - region.maxY,
                                           width: region.width, height: region.height)
                config.width = max(1, Int(region.width * screen.backingScaleFactor))
                config.height = max(1, Int(region.height * screen.backingScaleFactor))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 12)
                config.queueDepth = 3
                config.showsCursor = false
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
                self.stream = stream
                try await stream.startCapture()
                if cancelled {
                    try? await stream.stopCapture()
                    self.stream = nil
                    return
                }
                active = true
                completion(.success(()))
            } catch {
                self.stream = nil
                completion(.failure(error))
            }
        }
    }

    func stop() {
        cancelled = true
        active = false
        onFrame = nil
        let previous = stream
        stream = nil
        if let previous { Task { try? await previous.stopCapture() } }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active else { return }
            self.onError?(error.localizedDescription)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active else { return }
            self.onFrame?(cgImage)
        }
    }
}
