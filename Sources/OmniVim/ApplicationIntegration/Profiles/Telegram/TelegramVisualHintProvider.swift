import AppKit
import Darwin
import ScreenCaptureKit
import Vision

private struct TelegramCapturedWindow {
    let image: CGImage
    let frame: CGRect
}

private struct TelegramRecognizedText {
    let text: String
    let confidence: Float
    let frame: CGRect
}

@MainActor
final class TelegramVisualHintScanner {
    func elements(processIdentifier: pid_t) -> [UIElementHint] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        guard let capturedWindow = captureWindow(processIdentifier: processIdentifier) else {
            diagnosticLog(
                "Telegram visual scan pid=\(processIdentifier) capture=unavailable "
                    + "screenPermission=\(CGPreflightScreenCaptureAccess())"
            )
            return []
        }

        let observations = recognizeText(in: capturedWindow)
        let application = AXUIElementCreateApplication(processIdentifier)
        let editorFrame = focusedEditorFrame(in: application)
        let hints = layoutHints(
            observations: observations,
            windowFrame: capturedWindow.frame,
            editorFrame: editorFrame,
            application: application,
            processIdentifier: processIdentifier
        )
        let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000)
        diagnosticLog(
            "Telegram visual scan pid=\(processIdentifier) observations=\(observations.count) "
                + "hints=\(hints.count) elapsedMs=\(elapsedMilliseconds) "
                + "screenPermission=\(CGPreflightScreenCaptureAccess())"
        )
        return hints
    }

    private func captureWindow(processIdentifier: pid_t) -> TelegramCapturedWindow? {
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
        guard frame.width > 100, frame.height > 100 else {
            return nil
        }
        let image: CGImage?
        if #available(macOS 15.2, *) {
            image = screenCaptureKitImage(frame: frame)
        } else {
            image = legacyWindowImage(windowIdentifier: number.uint32Value)
        }
        guard let image else { return nil }
        return TelegramCapturedWindow(image: image, frame: frame)
    }

    @available(macOS 15.2, *)
    private func screenCaptureKitImage(frame: CGRect) -> CGImage? {
        let result = TelegramScreenCaptureResult()
        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(in: frame) { image, error in
            result.store(image: image, error: error)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 4) == .success else {
            diagnosticLog("Telegram ScreenCaptureKit capture timed out")
            return nil
        }
        if let error = result.error {
            diagnosticLog("Telegram ScreenCaptureKit capture failed error=\(error.localizedDescription)")
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
        let image = createImage(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            windowIdentifier,
            CGWindowImageOption.boundsIgnoreFraming.rawValue
        )
        return image?.takeRetainedValue()
    }

    private func recognizeText(in capturedWindow: TelegramCapturedWindow) -> [TelegramRecognizedText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        do {
            try VNImageRequestHandler(cgImage: capturedWindow.image).perform([request])
        } catch {
            diagnosticLog("Telegram visual OCR failed error=\(error.localizedDescription)")
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
            return TelegramRecognizedText(
                text: candidate.string,
                confidence: candidate.confidence,
                frame: frame
            )
        }
    }

    private func layoutHints(
        observations: [TelegramRecognizedText],
        windowFrame: CGRect,
        editorFrame: CGRect?,
        application: AXUIElement,
        processIdentifier: pid_t
    ) -> [UIElementHint] {
        let inferredSplit = telegramSidebarSplit(
            windowFrame: windowFrame,
            editorFrame: editorFrame
        )
        let splitX = min(
            windowFrame.maxX - 220,
            max(windowFrame.minX + 180, inferredSplit)
        )
        let sidebar = observations.filter {
            $0.frame.midX < splitX
                && $0.frame.minY >= windowFrame.minY + 140
                && $0.frame.maxY <= windowFrame.maxY - 60
        }
        let chatOriginY = windowFrame.minY + 140
        let sidebarGroups = groupByChatRow(
            sidebar,
            originY: chatOriginY,
            rowHeight: 70
        )
        var hints = sidebarGroups.compactMap {
            makeVisualHint(
                observations: $0.observations,
                role: "AXVisualRow",
                clippedTo: windowFrame,
                application: application,
                processIdentifier: processIdentifier,
                preferredFrame: CGRect(
                    x: windowFrame.minX,
                    y: chatOriginY + CGFloat($0.index) * 70,
                    width: splitX - windowFrame.minX,
                    height: 70
                )
            )
        }

        let header = observations.filter {
            $0.frame.midX >= splitX
                && $0.frame.minY >= windowFrame.minY + 20
                && $0.frame.maxY <= windowFrame.minY + 86
        }
        hints.append(contentsOf: groupByVisualRow(
            header,
            maximumGap: 8,
            maximumHeight: 52
        ).compactMap {
            makeVisualHint(
                observations: $0,
                role: "AXVisualControl",
                clippedTo: windowFrame,
                application: application,
                processIdentifier: processIdentifier
            )
        })
        hints.append(contentsOf: geometryHints(
            windowFrame: windowFrame,
            splitX: splitX,
            application: application,
            processIdentifier: processIdentifier
        ))
        return hints
    }

    private func groupByVisualRow(
        _ observations: [TelegramRecognizedText],
        maximumGap: CGFloat,
        maximumHeight: CGFloat
    ) -> [[TelegramRecognizedText]] {
        let sorted = observations.sorted {
            if abs($0.frame.minY - $1.frame.minY) > 3 { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX < $1.frame.minX
        }
        var groups: [[TelegramRecognizedText]] = []
        for observation in sorted {
            guard var last = groups.popLast() else {
                groups.append([observation])
                continue
            }
            let union = last.dropFirst().reduce(last[0].frame) { $0.union($1.frame) }
            let combined = union.union(observation.frame)
            if observation.frame.minY - union.maxY <= maximumGap,
               combined.height <= maximumHeight {
                last.append(observation)
                groups.append(last)
            } else {
                groups.append(last)
                groups.append([observation])
            }
        }
        return groups
    }

    private func groupByChatRow(
        _ observations: [TelegramRecognizedText],
        originY: CGFloat,
        rowHeight: CGFloat
    ) -> [(index: Int, observations: [TelegramRecognizedText])] {
        let grouped = Dictionary(grouping: observations) { observation in
            telegramChatRowIndex(
                y: observation.frame.midY,
                originY: originY,
                rowHeight: rowHeight
            )
        }
        return grouped.keys.sorted().compactMap { index in
            grouped[index].map { (index: index, observations: $0) }
        }
    }

    private func geometryHints(
        windowFrame: CGRect,
        splitX: CGFloat,
        application: AXUIElement,
        processIdentifier: pid_t
    ) -> [UIElementHint] {
        let headerY = windowFrame.minY + 50
        let footerY = windowFrame.maxY - 34
        let definitions: [(String, CGPoint)] = [
            ("Compose", CGPoint(x: splitX - 34, y: headerY)),
            ("Call", CGPoint(x: windowFrame.maxX - 143, y: headerY)),
            ("Search", CGPoint(x: windowFrame.maxX - 89, y: headerY)),
            ("More", CGPoint(x: windowFrame.maxX - 38, y: headerY)),
            ("Attach", CGPoint(x: splitX + 30, y: footerY)),
            ("Emoji", CGPoint(x: windowFrame.maxX - 77, y: footerY)),
            ("Voice", CGPoint(x: windowFrame.maxX - 35, y: footerY))
        ]
        var hints: [UIElementHint] = definitions.compactMap { title, point in
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
        let sidebarWidth = splitX - windowFrame.minX
        if sidebarWidth > 180 {
            hints.append(UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualControl",
                subrole: "",
                title: "Sidebar Search",
                frame: CGRect(
                    x: windowFrame.minX + 10,
                    y: windowFrame.minY + 72,
                    width: sidebarWidth - 20,
                    height: 32
                )
            ))
            hints.append(UIElementHint(
                element: application,
                processIdentifier: processIdentifier,
                role: "AXVisualRow",
                subrole: "",
                title: "Archived Chats",
                frame: CGRect(
                    x: windowFrame.minX,
                    y: windowFrame.minY + 112,
                    width: sidebarWidth,
                    height: 34
                )
            ))
        }
        return hints
    }

    private func makeVisualHint(
        observations: [TelegramRecognizedText],
        role: String,
        clippedTo windowFrame: CGRect,
        application: AXUIElement,
        processIdentifier: pid_t,
        preferredFrame: CGRect? = nil
    ) -> UIElementHint? {
        guard let first = observations.first else { return nil }
        let union = observations.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let padded = (preferredFrame ?? union.insetBy(dx: -6, dy: -6))
            .intersection(windowFrame)
        guard !padded.isNull, padded.width > 12, padded.height > 12 else { return nil }
        return UIElementHint(
            element: application,
            processIdentifier: processIdentifier,
            role: role,
            subrole: "",
            title: first.text,
            frame: padded
        )
    }

    private func focusedEditorFrame(in application: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXEditorResolver().frame(of: value as! AXUIElement)
    }
}

func telegramSidebarSplit(windowFrame: CGRect, editorFrame: CGRect?) -> CGFloat {
    let defaultSplit = windowFrame.minX + windowFrame.width * 0.33
    guard let editorSplit = editorFrame.map({ $0.minX - 60 }),
          editorSplit >= windowFrame.minX + windowFrame.width * 0.25,
          editorSplit <= windowFrame.minX + windowFrame.width * 0.55 else {
        return defaultSplit
    }
    return editorSplit
}

func telegramChatRowIndex(y: CGFloat, originY: CGFloat, rowHeight: CGFloat) -> Int {
    guard rowHeight > 0 else { return 0 }
    return max(0, Int(floor((y - originY) / rowHeight)))
}

private final class TelegramScreenCaptureResult: @unchecked Sendable {
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

struct TelegramHintProvider: AdapterHintProviding {
    private let hasScreenCaptureAccess: () -> Bool

    init(
        hasScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.hasScreenCaptureAccess = hasScreenCaptureAccess
    }

    var discoveryLimitation: HintDiscoveryLimitation? {
        hasScreenCaptureAccess()
            ? nil
            : .screenRecordingPermissionRequired(applicationName: "Telegram")
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
        let accessibilityHints = AXHitTestHintScanner().elements(
            processIdentifier: processIdentifier
        )
        if searchOnly {
            return accessibilityHints.filter {
                ["AXTextField", "AXTextArea", "AXSearchField"].contains($0.role)
            }
        }

        let visualHints = TelegramVisualHintScanner().elements(
            processIdentifier: processIdentifier
        )
        return accessibilityHints + visualHints.filter { visual in
            !accessibilityHints.contains { accessibility in
                overlapRatio(accessibility.frame, visual.frame) >= 0.7
            }
        }
    }

    private func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let denominator = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard denominator > 0 else { return 0 }
        return intersection.width * intersection.height / denominator
    }
}
