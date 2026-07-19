import AppKit
import Darwin
import ScreenCaptureKit

struct GPAHintConfiguration: Equatable, Sendable {
    let applicationName: String
    let minimumConfidence: Float
    let maximumElementAreaRatio: CGFloat

    static let telegram = GPAHintConfiguration(
        applicationName: "Telegram",
        minimumConfidence: 0.30,
        maximumElementAreaRatio: 0.20
    )

    static let weChat = GPAHintConfiguration(
        applicationName: "WeChat",
        minimumConfidence: 0.30,
        maximumElementAreaRatio: 0.20
    )
}

struct CapturedApplicationWindow: @unchecked Sendable {
    let image: CGImage
    let frame: CGRect
}

@MainActor
final class ApplicationWindowCapturer {
    func capture(processIdentifier: pid_t, applicationName: String) -> CapturedApplicationWindow? {
        guard let windowInfo = frontWindowInfo(processIdentifier: processIdentifier),
              let number = windowInfo[kCGWindowNumber as String] as? NSNumber,
              let bounds = windowInfo[kCGWindowBounds as String] as? [String: NSNumber],
              let x = bounds["X"],
              let y = bounds["Y"],
              let width = bounds["Width"],
              let height = bounds["Height"] else { return nil }
        let frame = CGRect(
            x: x.doubleValue,
            y: y.doubleValue,
            width: width.doubleValue,
            height: height.doubleValue
        )
        guard frame.width > 100, frame.height > 100 else { return nil }

        let image: CGImage?
        if #available(macOS 15.2, *) {
            image = screenCaptureKitImage(frame: frame, applicationName: applicationName)
        } else {
            image = legacyWindowImage(windowIdentifier: number.uint32Value)
        }
        guard let image else { return nil }
        return CapturedApplicationWindow(image: image, frame: frame)
    }

    @available(macOS 15.2, *)
    private func screenCaptureKitImage(frame: CGRect, applicationName: String) -> CGImage? {
        let result = ScreenCaptureResult()
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(in: frame) { image, error in
            result.store(image: image, error: error)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 4) == .success else {
            diagnosticLog("\(applicationName) ScreenCaptureKit capture timed out")
            return nil
        }
        if let error = result.error {
            diagnosticLog(
                "\(applicationName) ScreenCaptureKit capture failed error=\(error.localizedDescription)"
            )
        }
        return result.image
    }

    private func frontWindowInfo(processIdentifier: pid_t) -> [String: Any]? {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        return raw.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }.max {
            windowArea($0) < windowArea($1)
        }
    }

    private func windowArea(_ info: [String: Any]) -> Double {
        guard let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
              let width = bounds["Width"],
              let height = bounds["Height"] else { return 0 }
        return width.doubleValue * height.doubleValue
    }

    private func legacyWindowImage(windowIdentifier: CGWindowID) -> CGImage? {
        typealias CreateWindowImage = @convention(c) (
            CGRect,
            UInt32,
            CGWindowID,
            UInt32
        ) -> Unmanaged<CGImage>?

        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_LAZY
        ) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let createImage = unsafeBitCast(symbol, to: CreateWindowImage.self)
        return createImage(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            windowIdentifier,
            CGWindowImageOption.boundsIgnoreFraming.rawValue
        )?.takeRetainedValue()
    }
}

@MainActor
final class GPAVisualHintScanner {
    private let configuration: GPAHintConfiguration
    private let capturer: ApplicationWindowCapturer
    private let injectedDetectorResult: Result<GPAElementDetector, Error>?

    init(
        configuration: GPAHintConfiguration,
        capturer: ApplicationWindowCapturer = ApplicationWindowCapturer(),
        detectorResult: Result<GPAElementDetector, Error>? = nil
    ) {
        self.configuration = configuration
        self.capturer = capturer
        injectedDetectorResult = detectorResult
    }

    func elements(processIdentifier: pid_t) -> [UIElementHint] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let captureStartedAt = CFAbsoluteTimeGetCurrent()
        guard let capturedWindow = capturer.capture(
            processIdentifier: processIdentifier,
            applicationName: configuration.applicationName
        ) else {
            diagnosticLog(
                "\(configuration.applicationName) GPA-only scan pid=\(processIdentifier) "
                    + "capture=unavailable screenPermission=\(CGPreflightScreenCaptureAccess())"
            )
            return []
        }
        let captureMilliseconds = milliseconds(since: captureStartedAt)

        let modelLoadStartedAt = CFAbsoluteTimeGetCurrent()
        let detectorResult = injectedDetectorResult ?? GPAElementDetector.defaultResult
        let modelLoadMilliseconds = milliseconds(since: modelLoadStartedAt)
        let detector: GPAElementDetector
        switch detectorResult {
        case .success(let availableDetector):
            detector = availableDetector
        case .failure(let error):
            diagnosticLog(
                "\(configuration.applicationName) GPA-only scan model=unavailable "
                    + "captureMs=\(captureMilliseconds) modelLoadMs=\(modelLoadMilliseconds) "
                    + "totalMs=\(milliseconds(since: startedAt)) "
                    + "error=\(error.localizedDescription)"
            )
            return []
        }

        let inferenceStartedAt = CFAbsoluteTimeGetCurrent()
        let rawDetections: [GPAGUIElementDetection]
        do {
            rawDetections = try detector.detect(
                in: capturedWindow.image,
                minimumConfidence: configuration.minimumConfidence
            )
        } catch {
            diagnosticLog(
                "\(configuration.applicationName) GPA-only scan inference=failed "
                    + "captureMs=\(captureMilliseconds) modelLoadMs=\(modelLoadMilliseconds) "
                    + "inferenceMs=\(milliseconds(since: inferenceStartedAt)) "
                    + "totalMs=\(milliseconds(since: startedAt)) "
                    + "error=\(error.localizedDescription)"
            )
            return []
        }
        let inferenceMilliseconds = milliseconds(since: inferenceStartedAt)

        let application = AXUIElementCreateApplication(processIdentifier)
        let windowArea = capturedWindow.frame.width * capturedWindow.frame.height
        let hints = rawDetections.compactMap { detection -> UIElementHint? in
            let frame = detection.globalFrame(in: capturedWindow.frame)
                .intersection(capturedWindow.frame)
            let area = frame.width * frame.height
            guard detection.confidence >= configuration.minimumConfidence,
                  !frame.isNull,
                  frame.width >= 10,
                  frame.height >= 10,
                  area <= windowArea * configuration.maximumElementAreaRatio else { return nil }
            return UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualControl",
                subrole: "GPAInteractiveElement",
                title: String(format: "GPA %.2f", detection.confidence),
                frame: frame
            )
        }
        diagnosticLog(
            "\(configuration.applicationName) GPA-only scan pid=\(processIdentifier) "
                + "raw=\(rawDetections.count) accepted=\(hints.count) "
                + "captureMs=\(captureMilliseconds) modelLoadMs=\(modelLoadMilliseconds) "
                + "inferenceMs=\(inferenceMilliseconds) totalMs=\(milliseconds(since: startedAt)) "
                + "screenPermission=\(CGPreflightScreenCaptureAccess())"
        )
#if DEBUG
        for (index, hint) in hints.prefix(250).enumerated() {
            diagnosticLog(
                "\(configuration.applicationName) GPA detection index=\(index) "
                    + "confidence=\(hint.title) frame=x=\(Int(hint.frame.minX)) "
                    + "y=\(Int(hint.frame.minY)) w=\(Int(hint.frame.width)) "
                    + "h=\(Int(hint.frame.height))"
            )
        }
#endif
        return hints
    }

    private func milliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }
}

struct GPAHintProvider: AdapterHintProviding {
    let configuration: GPAHintConfiguration
    private let hasScreenCaptureAccess: () -> Bool

    init(
        configuration: GPAHintConfiguration,
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.configuration = configuration
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
    }

    var discoveryLimitation: HintDiscoveryLimitation? {
        hasScreenCaptureAccess()
            ? nil
            : .screenRecordingPermissionRequired(
                applicationName: configuration.applicationName
            )
    }

    @MainActor
    func hints(searchOnly: Bool, scanner: AccessibilityScanner) -> [UIElementHint] {
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return []
        }
        return hints(processIdentifier: processIdentifier, searchOnly: searchOnly)
    }

    @MainActor
    func hints(processIdentifier: pid_t, searchOnly: Bool) -> [UIElementHint] {
        if searchOnly {
            return AXHitTestHintScanner().elements(
                processIdentifier: processIdentifier
            ).filter {
                ["AXTextField", "AXTextArea", "AXSearchField"].contains($0.role)
            }
        }

        return GPAVisualHintScanner(configuration: configuration).elements(
            processIdentifier: processIdentifier
        )
    }
}

private final class ScreenCaptureResult: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var image: CGImage?
    private(set) var error: Error?

    func store(image: CGImage?, error: Error?) {
        lock.lock()
        self.image = image
        self.error = error
        lock.unlock()
    }
}
