import AppKit

enum ScreenshotCaptureResult {
    case image(Data)
    case cancelled
    case copiedToClipboard
    case failed(String)
}

final class ScreenshotCaptureService {
    private var process: Process?
    private var captureDirectory: URL?

    init() {
        let root = FileManager.default.temporaryDirectory
        guard let children = try? FileManager.default.contentsOfDirectory(at: root,
                                                                          includingPropertiesForKeys: [.creationDateKey]) else { return }
        for child in children where child.lastPathComponent.hasPrefix("PasterCapture-") {
            let created = (try? child.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if Date().timeIntervalSince(created) > 86_400 { try? FileManager.default.removeItem(at: child) }
        }
    }

    var isCapturing: Bool { process != nil }

    func captureRegion(completion: @escaping (ScreenshotCaptureResult) -> Void) {
        guard process == nil else { completion(.failed("已有截图正在进行")); return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasterCapture-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { completion(.failed("无法创建截图临时目录")); return }
        let file = directory.appendingPathComponent("capture.png")
        let boardCount = NSPasteboard.general.changeCount
        let task = Process()
        let errors = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-s", "-x", "-t", "png", file.path]
        task.standardError = errors
        task.terminationHandler = { [weak self] finished in
            errors.fileHandleForWriting.closeFile()
            let details = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                let result: ScreenshotCaptureResult
                if let data = try? Data(contentsOf: file), let rep = NSBitmapImageRep(data: data),
                   rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                    result = .image(data)
                } else if NSPasteboard.general.changeCount != boardCount {
                    result = .copiedToClipboard
                } else if details.localizedCaseInsensitiveContains("cancel") ||
                            (finished.terminationStatus == 1 && details.isEmpty) {
                    result = .cancelled
                } else {
                    result = .failed("系统截图未生成图片。若录屏权限已开启且 Paster 刚更新，请在系统设置中移除旧 Paster 条目，重新添加当前应用，再退出并重新打开 Paster。")
                }
                self.process = nil
                self.captureDirectory = nil
                try? FileManager.default.removeItem(at: directory)
                completion(result)
            }
        }
        do {
            try task.run()
            process = task
            captureDirectory = directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            completion(.failed("无法启动系统截图：\(error.localizedDescription)"))
        }
    }

    func cancel() {
        if let process, process.isRunning { process.terminate() }
    }
}
