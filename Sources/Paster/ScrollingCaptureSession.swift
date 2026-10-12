import AppKit
import CoreGraphics

private final class FrameStabilityCheck {
    private var previous: [UInt8]?

    func isStable(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 48 * 48)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 48, height: 48,
                                          bitsPerComponent: 8, bytesPerRow: 48,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: 48, height: 48))
            return true
        }
        guard drawn else { return false }
        defer { previous = pixels }
        guard let previous else { return false }
        let error = zip(pixels, previous).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(error) / Double(pixels.count) < 2.5
    }
}

final class ScrollingCaptureSession {
    private let target: NSRunningApplication
    private let screen: NSScreen
    private let region: NSRect
    private let source = ScrollingFrameSource()
    private let gate = ManualScrollGate()
    private let marker = Int64.random(in: 1...Int64.max)
    private lazy var detector = ManualScrollDetector(gate: gate, marker: marker)
    private lazy var driver = ScrollDriver(gate: gate, marker: marker)
    private let stitchQueue = DispatchQueue(label: "Paster.FrameStitch", qos: .userInitiated)
    private let stitcher = FrameStitcher()
    private let stability = FrameStabilityCheck()
    private var latestFrame: CGImage?
    private var timer: Timer?
    private var startedAt = Date()
    private var acceptedSamples = 0
    private var noMovementCount = 0
    private var processing = false
    private var waitingForOwnScroll = false
    private var lastPostTime: Date?
    private var finished = false
    var onStatus: ((String) -> Void)?
    var onComplete: ((Data?, String?) -> Void)?

    init(target: NSRunningApplication, screen: NSScreen, region: NSRect) {
        self.target = target
        self.screen = screen
        self.region = region
    }

    func start() {
        detector.onTakeover = { [weak self] in self?.onStatus?("手动滚动 · 完成后从菜单栏停止并预览") }
        if !AXIsProcessTrusted() || !detector.start() {
            _ = gate.takeOver()
            onStatus?("手动滚动 · 自动滚动所需权限不可用")
        } else {
            onStatus?("自动滚动 · 手动操作将立即接管")
        }
        source.onFrame = { [weak self] frame in self?.latestFrame = frame }
        source.onError = { [weak self] error in self?.finish(message: "画面捕获中断：\(error)") }
        source.start(screen: screen, region: region) { [weak self] result in
            guard let self, !self.finished else { return }
            switch result {
            case .success:
                self.startedAt = Date()
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.tick() }
            case .failure(let error):
                self.finish(message: "无法开始滚动截图：\(error.localizedDescription)。若刚授予录屏权限，请重启 Paster 后重试。")
            }
        }
    }

    func stopAndPreview() { finish(message: nil) }
    func cancel() {
        onComplete = nil
        finish(message: nil)
    }

    private func tick() {
        guard !finished, !processing else { return }
        if target.isTerminated {
            finish(message: "目标应用已关闭")
            return
        }
        if Date().timeIntervalSince(startedAt) >= 120 || acceptedSamples >= 60 {
            finish(message: "已达到本次截图上限")
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != target.processIdentifier &&
            front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            finish(message: "目标应用已切换")
            return
        }
        guard let frame = latestFrame, stability.isStable(frame) else { return }
        if let lastPostTime, Date().timeIntervalSince(lastPostTime) < 0.8 { return }
        if waitingForOwnScroll, let lastPostTime,
           Date().timeIntervalSince(lastPostTime) > 1.0 && !detector.observedOwnScroll {
            switchToManual("无法确认自动滚动事件，已切换手动")
        }
        processing = true
        stitchQueue.async { [weak self] in
            guard let self else { return }
            let result = self.stitcher.append(frame)
            DispatchQueue.main.async { [weak self] in self?.processed(result) }
        }
    }

    private func processed(_ result: StitchResult) {
        processing = false
        guard !finished else { return }
        switch result {
        case .started, .added:
            acceptedSamples += 1
            noMovementCount = 0
            if case .added = result, gate.mode == .automatic,
               lastPostTime.map({ Date().timeIntervalSince($0) > 1.5 }) ?? true {
                switchToManual("检测到非自动滚动引起的画面变化，已切换手动")
            }
            onStatus?("\(gate.mode == .automatic ? "自动" : "手动")滚动 · 已采样 \(acceptedSamples) 段")
        case .noMovement:
            noMovementCount += 1
            if waitingForOwnScroll && !detector.observedOwnScroll { switchToManual("无法确认自动滚动事件，已切换手动") }
            if gate.mode == .automatic && noMovementCount >= 2 {
                switchToManual("自动滚动未产生位移，请手动滚动或停止并预览")
            }
        case .unreliable:
            finish(message: "画面重叠无法可靠匹配，已保留可用部分")
            return
        case .pixelLimit:
            finish(message: "已达到 2500 万像素上限")
            return
        }
        guard gate.mode == .automatic else { return }
        if case .noMovement = result, noMovementCount == 1 { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: region.midX, y: primaryTop - region.midY)
        waitingForOwnScroll = driver.postStep(at: point)
        if waitingForOwnScroll { lastPostTime = Date() }
        if !waitingForOwnScroll { switchToManual("无法发送自动滚动事件，请手动滚动") }
    }

    private func switchToManual(_ message: String) {
        if gate.takeOver() { onStatus?(message) }
    }

    private func finish(message: String?) {
        guard !finished else { return }
        finished = true
        gate.stop()
        detector.stop()
        timer?.invalidate()
        timer = nil
        source.stop()
        latestFrame = nil
        stitchQueue.async { [weak self] in
            guard let self else { return }
            let png = self.stitcher.png()
            DispatchQueue.main.async { [weak self] in self?.onComplete?(png, message) }
        }
    }
}
