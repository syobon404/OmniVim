import AppKit
import Darwin
import ScreenCaptureKit
import Vision

private struct WeChatCapturedWindow {
    let image: CGImage
    let frame: CGRect
}

private struct WeChatRecognizedText {
    let text: String
    let frame: CGRect
}

@MainActor
final class WeChatVisualHintScanner {
    private let injectedDetectorResult: Result<GPAElementDetector, Error>?

    init(detectorResult: Result<GPAElementDetector, Error>? = nil) {
        injectedDetectorResult = detectorResult
    }

    func elements(processIdentifier: pid_t) -> [UIElementHint] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let captureStartedAt = CFAbsoluteTimeGetCurrent()
        guard let capturedWindow = captureWindow(processIdentifier: processIdentifier) else {
            diagnosticLog(
                "WeChat GPA-only scan pid=\(processIdentifier) capture=unavailable "
                    + "screenPermission=\(CGPreflightScreenCaptureAccess())"
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
                "WeChat GPA-only scan model=unavailable "
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
                minimumConfidence: 0.05
            )
        } catch {
            diagnosticLog(
                "WeChat GPA-only scan inference=failed "
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
            guard detection.confidence >= 0.20 else { return nil }
            let frame = detection.globalFrame(in: capturedWindow.frame)
                .intersection(capturedWindow.frame)
            let area = frame.width * frame.height
            guard !frame.isNull,
                  frame.width >= 10,
                  frame.height >= 10,
                  area <= windowArea * 0.20 else { return nil }
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
            "WeChat GPA-only scan pid=\(processIdentifier) raw=\(rawDetections.count) "
                + "accepted=\(hints.count) captureMs=\(captureMilliseconds) "
                + "modelLoadMs=\(modelLoadMilliseconds) inferenceMs=\(inferenceMilliseconds) "
                + "totalMs=\(milliseconds(since: startedAt)) "
                + "screenPermission=\(CGPreflightScreenCaptureAccess())"
        )
#if DEBUG
        for (index, hint) in hints.prefix(250).enumerated() {
            diagnosticLog(
                "WeChat GPA detection index=\(index) confidence=\(hint.title) "
                    + "frame=x=\(Int(hint.frame.minX)) y=\(Int(hint.frame.minY)) "
                    + "w=\(Int(hint.frame.width)) h=\(Int(hint.frame.height))"
            )
        }
#endif
        return hints
    }

    private func milliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    private func captureWindow(processIdentifier: pid_t) -> WeChatCapturedWindow? {
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
        guard frame.width > 420, frame.height > 360 else { return nil }

        let image: CGImage?
        if #available(macOS 15.2, *) {
            image = screenCaptureKitImage(frame: frame)
        } else {
            image = legacyWindowImage(windowIdentifier: number.uint32Value)
        }
        guard let image else { return nil }
        return WeChatCapturedWindow(image: image, frame: frame)
    }

    @available(macOS 15.2, *)
    private func screenCaptureKitImage(frame: CGRect) -> CGImage? {
        let result = WeChatScreenCaptureResult()
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(in: frame) { image, error in
            result.store(image: image, error: error)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 4) == .success else {
            diagnosticLog("WeChat ScreenCaptureKit capture timed out")
            return nil
        }
        if let error = result.error {
            diagnosticLog("WeChat ScreenCaptureKit capture failed error=\(error.localizedDescription)")
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

    private func recognizeText(in capturedWindow: WeChatCapturedWindow) -> [WeChatRecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        do {
            try VNImageRequestHandler(cgImage: capturedWindow.image).perform([request])
        } catch {
            diagnosticLog("WeChat visual OCR failed error=\(error.localizedDescription)")
            return []
        }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= 0.3 else { return nil }
            let normalized = observation.boundingBox
            let frame = CGRect(
                x: capturedWindow.frame.minX + normalized.minX * capturedWindow.frame.width,
                y: capturedWindow.frame.minY + (1 - normalized.maxY) * capturedWindow.frame.height,
                width: normalized.width * capturedWindow.frame.width,
                height: normalized.height * capturedWindow.frame.height
            )
            guard frame.width > 8, frame.height > 6 else { return nil }
            return WeChatRecognizedText(text: candidate.string, frame: frame)
        }
    }

    private func layoutHints(
        observations: [WeChatRecognizedText],
        windowFrame: CGRect,
        application: AXUIElement,
        processIdentifier: pid_t
    ) -> [UIElementHint] {
        let splitX = wechatSidebarSplit(windowFrame: windowFrame)
        let navigationX = windowFrame.minX + 60
        let chatOriginY = windowFrame.minY + 48
        let rowHeight: CGFloat = 69
        let sidebar = observations.filter {
            $0.frame.midX >= navigationX
                && $0.frame.midX < splitX
                && $0.frame.minY >= chatOriginY
                && $0.frame.maxY <= windowFrame.maxY - 20
        }
        let sidebarGroups = Dictionary(grouping: sidebar) {
            wechatChatRowIndex(
                y: $0.frame.midY,
                originY: chatOriginY,
                rowHeight: rowHeight
            )
        }
        let lastDetectedRow = sidebarGroups.keys.max() ?? -1
        let lastVisibleRow = sidebar.isEmpty
            ? -1
            : min(12, Int(floor((windowFrame.maxY - 20 - chatOriginY) / rowHeight)))
        diagnosticLog(
            "WeChat visual layout sidebarObservations=\(sidebar.count) "
                + "detectedRows=\(sidebarGroups.count) lastDetectedRow=\(lastDetectedRow) "
                + "lastVisibleRow=\(lastVisibleRow)"
        )
        var hints = (lastVisibleRow >= 0 ? Array(0...lastVisibleRow) : []).compactMap {
            index -> UIElementHint? in
            let frame = CGRect(
                x: navigationX,
                y: chatOriginY + CGFloat(index) * rowHeight,
                width: splitX - navigationX,
                height: rowHeight
            ).intersection(windowFrame)
            guard !frame.isNull, frame.width > 80, frame.height > 20 else { return nil }
            return UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualRow",
                subrole: "",
                title: sidebarGroups[index]?.first?.text ?? "Chat Row \(index + 1)",
                frame: frame
            )
        }
        hints.append(contentsOf: geometryHints(
            windowFrame: windowFrame,
            splitX: splitX,
            application: application,
            processIdentifier: processIdentifier
        ))
        return hints
    }

    private func geometryHints(
        windowFrame: CGRect,
        splitX: CGFloat,
        application: AXUIElement,
        processIdentifier: pid_t
    ) -> [UIElementHint] {
        let toolbarY = max(windowFrame.minY + 120, windowFrame.maxY - 250)
        let pointDefinitions: [(String, CGPoint)] = [
            ("Chats", CGPoint(x: windowFrame.minX + 30, y: windowFrame.minY + 128)),
            ("Contacts", CGPoint(x: windowFrame.minX + 30, y: windowFrame.minY + 176)),
            ("Favorites", CGPoint(x: windowFrame.minX + 30, y: windowFrame.minY + 224)),
            ("Mini Programs", CGPoint(x: windowFrame.minX + 30, y: windowFrame.minY + 272)),
            ("Moments", CGPoint(x: windowFrame.minX + 30, y: windowFrame.minY + 320)),
            ("Channels", CGPoint(x: windowFrame.minX + 30, y: windowFrame.minY + 368)),
            ("Mobile", CGPoint(x: windowFrame.minX + 30, y: windowFrame.maxY - 150)),
            ("Menu", CGPoint(x: windowFrame.minX + 30, y: windowFrame.maxY - 101)),
            ("New Chat", CGPoint(x: splitX - 27, y: windowFrame.minY + 32)),
            ("Chat Actions", CGPoint(x: windowFrame.maxX - 90, y: windowFrame.minY + 32)),
            ("More", CGPoint(x: windowFrame.maxX - 32, y: windowFrame.minY + 32)),
            ("Emoji", CGPoint(x: splitX + 28, y: toolbarY)),
            ("Apps", CGPoint(x: splitX + 68, y: toolbarY)),
            ("Files", CGPoint(x: splitX + 108, y: toolbarY)),
            ("Screenshot", CGPoint(x: splitX + 148, y: toolbarY)),
            ("Voice", CGPoint(x: splitX + 205, y: toolbarY)),
            ("Call", CGPoint(x: windowFrame.maxX - 65, y: toolbarY)),
            ("Video", CGPoint(x: windowFrame.maxX - 25, y: toolbarY))
        ]
        var hints = pointDefinitions.compactMap { title, point -> UIElementHint? in
            guard windowFrame.contains(point) else { return nil }
            return UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualControl",
                subrole: "",
                title: title,
                frame: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)
            )
        }

        let searchFrame = CGRect(
            x: windowFrame.minX + 72,
            y: windowFrame.minY + 17,
            width: max(40, splitX - windowFrame.minX - 121),
            height: 30
        ).intersection(windowFrame)
        if searchFrame.width > 40 {
            hints.append(UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualControl",
                subrole: "",
                title: "Search",
                frame: searchFrame
            ))
        }

        let editorFrame = CGRect(
            x: splitX + 8,
            y: toolbarY + 24,
            width: windowFrame.maxX - splitX - 16,
            height: max(40, windowFrame.maxY - toolbarY - 32)
        ).intersection(windowFrame)
        if editorFrame.width > 100, editorFrame.height > 30 {
            hints.append(UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualControl",
                subrole: "",
                title: "Message Editor",
                frame: editorFrame
            ))
        }
        return hints
    }
}

func wechatSidebarSplit(windowFrame: CGRect) -> CGFloat {
    let sidebarWidth = min(300, max(240, windowFrame.width * 0.39))
    return min(windowFrame.maxX - 260, windowFrame.minX + sidebarWidth)
}

func wechatChatRowIndex(y: CGFloat, originY: CGFloat, rowHeight: CGFloat) -> Int {
    guard rowHeight > 0 else { return 0 }
    return max(0, Int(floor((y - originY) / rowHeight)))
}

private final class WeChatScreenCaptureResult: @unchecked Sendable {
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

struct WeChatHintProvider: AdapterHintProviding {
    private let hasScreenCaptureAccess: () -> Bool

    init(
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
    }

    var discoveryLimitation: HintDiscoveryLimitation? {
        hasScreenCaptureAccess()
            ? nil
            : .screenRecordingPermissionRequired(applicationName: "WeChat")
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

        return WeChatVisualHintScanner().elements(
            processIdentifier: processIdentifier
        )
    }
}
