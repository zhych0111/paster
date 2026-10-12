import AppKit

/// Exercises both capture APIs from the actual app identity. Only result metadata is retained.
final class CaptureSelfTest {
    private let source = ScrollingFrameSource()
    private let output: URL?
    private var process: Process?
    private var finished = false
    private var nativeCompleted = false
    private var result: [String: Any] = ["preflight": CGPreflightScreenCaptureAccess(),
                                       "bundleID": Bundle.main.bundleIdentifier ?? "none"]

    init(output: URL?) { self.output = output }

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments
        let index = arguments.firstIndex(of: "--diagnostic-output")
        let output = index.flatMap { $0 + 1 < arguments.count ? URL(fileURLWithPath: arguments[$0 + 1]) : nil }
        let test = CaptureSelfTest(output: output)
        DispatchQueue.main.async { test.start() }
        withExtendedLifetime(test) { app.run() }
    }

    private func start() {
        guard let screen = NSScreen.screens.first else { finish("no-display"); return }
        let region = NSRect(x: screen.frame.minX + 8, y: screen.frame.maxY - 16, width: 8, height: 8)
        source.onFrame = { [weak self] image in
            guard let self, !self.finished, !self.nativeCompleted else { return }
            self.nativeCompleted = true
            self.result["nativeFrame"] = ["width": image.width, "height": image.height]
            self.source.stop()
            self.checkSystemCapture()
        }
        source.start(screen: screen, region: region) { [weak self] capture in
            guard let self, !self.finished else { return }
            if case .failure(let error) = capture {
                let error = error as NSError
                self.result["errorDomain"] = error.domain
                self.result["errorCode"] = error.code
                self.finish("native-failed")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.finished else { return }
            self.finish("timeout")
        }
    }

    private func checkSystemCapture() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PasterCapture-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { finish("temporary-directory-failed"); return }
        let file = directory.appendingPathComponent("test.png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-R", "8,8,8,8", "-t", "png", file.path]
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                guard let self else { try? FileManager.default.removeItem(at: directory); return }
                let rep = (try? Data(contentsOf: file)).flatMap(NSBitmapImageRep.init(data:))
                self.result["systemCaptureExit"] = task.terminationStatus
                if let rep { self.result["systemFrame"] = ["width": rep.pixelsWide, "height": rep.pixelsHigh] }
                try? FileManager.default.removeItem(at: directory)
                self.process = nil
                self.finish(rep == nil ? "system-failed" : "passed")
            }
        }
        do { try task.run(); process = task }
        catch { try? FileManager.default.removeItem(at: directory); finish("system-launch-failed") }
    }

    private func finish(_ status: String) {
        guard !finished else { return }
        finished = true
        source.stop()
        if process?.isRunning == true { process?.terminate() }
        result["status"] = status
        if let output, let json = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? json.write(to: output, options: .atomic)
        }
        print("Paster capture self-test: \(status)")
        exit(status == "passed" ? 0 : 1)
    }
}
