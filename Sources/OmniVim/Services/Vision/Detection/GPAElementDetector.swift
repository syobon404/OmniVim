import CoreGraphics
import CoreML
import Foundation
import Vision

struct GPAGUIElementDetection: Equatable, Sendable {
    let normalizedFrame: CGRect
    let confidence: Float
    let identifier: String

    func globalFrame(in capturedWindowFrame: CGRect) -> CGRect {
        CGRect(
            x: capturedWindowFrame.minX + normalizedFrame.minX * capturedWindowFrame.width,
            y: capturedWindowFrame.minY + (1 - normalizedFrame.maxY) * capturedWindowFrame.height,
            width: normalizedFrame.width * capturedWindowFrame.width,
            height: normalizedFrame.height * capturedWindowFrame.height
        )
    }
}

struct GPADetectionSuppressor {
    var intersectionOverUnionThreshold: CGFloat = 0.35
    var containmentThreshold: CGFloat = 0.90
    var minimumAreaSimilarity: CGFloat = 0.50

    func suppress(_ detections: [GPAGUIElementDetection]) -> [GPAGUIElementDetection] {
        let ranked = detections.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            let lhsArea = area(of: lhs.normalizedFrame)
            let rhsArea = area(of: rhs.normalizedFrame)
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            if lhs.normalizedFrame.minY != rhs.normalizedFrame.minY {
                return lhs.normalizedFrame.minY < rhs.normalizedFrame.minY
            }
            return lhs.normalizedFrame.minX < rhs.normalizedFrame.minX
        }

        var accepted: [GPAGUIElementDetection] = []
        for candidate in ranked {
            guard !accepted.contains(where: { overlapsSameElement(candidate, $0) }) else {
                continue
            }
            accepted.append(candidate)
        }
        return accepted
    }

    private func overlapsSameElement(
        _ lhs: GPAGUIElementDetection,
        _ rhs: GPAGUIElementDetection
    ) -> Bool {
        let lhsArea = area(of: lhs.normalizedFrame)
        let rhsArea = area(of: rhs.normalizedFrame)
        guard lhsArea > 0, rhsArea > 0 else { return false }

        let intersectionArea = area(of: lhs.normalizedFrame.intersection(rhs.normalizedFrame))
        guard intersectionArea > 0 else { return false }
        let unionArea = lhsArea + rhsArea - intersectionArea
        let intersectionOverUnion = intersectionArea / unionArea
        if intersectionOverUnion >= intersectionOverUnionThreshold {
            return true
        }

        let containment = intersectionArea / min(lhsArea, rhsArea)
        let areaSimilarity = min(lhsArea, rhsArea) / max(lhsArea, rhsArea)
        return containment >= containmentThreshold && areaSimilarity >= minimumAreaSimilarity
    }

    private func area(of frame: CGRect) -> CGFloat {
        guard !frame.isNull, !frame.isInfinite else { return 0 }
        return max(0, frame.width) * max(0, frame.height)
    }
}

enum GPAElementDetectorError: LocalizedError {
    case bundledModelNotFound(name: String)
    case modelNotFound(searchedPaths: [String])
    case unexpectedResultType(String)

    var errorDescription: String? {
        switch self {
        case .bundledModelNotFound(let name):
            "Core ML model \(name).mlmodelc was not found in the application bundle."
        case .modelNotFound(let searchedPaths):
            "GPA Core ML model was not found at: \(searchedPaths.joined(separator: ", "))"
        case .unexpectedResultType(let type):
            "GPA detector returned \(type); export the model with embedded NMS."
        }
    }
}

/// Runs the GPA GUI element detector through Vision.
///
/// `detect(in:minimumConfidence:)` is synchronous. Call it from a dedicated background task or
/// queue so a 1280-point inference cannot block the app's main actor.
final class GPAElementDetector {
    private let model: VNCoreMLModel

    @MainActor
    static let defaultResult: Result<GPAElementDetector, Error> = Result {
        try GPAElementDetector.loadDefault()
    }

    convenience init(
        bundle: Bundle = .main,
        resourceName: String = "GPA_GUI_Detector",
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws {
        guard let modelURL = bundle.url(forResource: resourceName, withExtension: "mlmodelc") else {
            throw GPAElementDetectorError.bundledModelNotFound(name: resourceName)
        }
        try self.init(compiledModelURL: modelURL, configuration: configuration)
    }

    init(
        compiledModelURL: URL,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws {
        configuration.computeUnits = .all
        let coreMLModel = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        model = try VNCoreMLModel(for: coreMLModel)
    }

    convenience init(
        modelURL: URL,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws {
        let compiledURL: URL
        if modelURL.pathExtension == "mlmodelc" {
            compiledURL = modelURL
        } else {
            compiledURL = try MLModel.compileModel(at: modelURL)
        }
        try self.init(compiledModelURL: compiledURL, configuration: configuration)
    }

    func detect(
        in image: CGImage,
        minimumConfidence: Float = 0.15
    ) throws -> [GPAGUIElementDetection] {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])

        guard let results = request.results else { return [] }
        guard let observations = results as? [VNRecognizedObjectObservation] else {
            let resultType = results.first.map { String(describing: type(of: $0)) } ?? "no observations"
            throw GPAElementDetectorError.unexpectedResultType(resultType)
        }

        let detections: [GPAGUIElementDetection] = observations.compactMap { observation in
            let label = observation.labels.first
            let confidence = label?.confidence ?? observation.confidence
            guard confidence >= minimumConfidence else { return nil }
            return GPAGUIElementDetection(
                normalizedFrame: observation.boundingBox,
                confidence: confidence,
                identifier: label?.identifier ?? "interactive"
            )
        }
        return GPADetectionSuppressor().suppress(detections)
    }

    private static func loadDefault(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> GPAElementDetector {
        if let bundledURL = bundle.url(
            forResource: "GPA_GUI_Detector",
            withExtension: "mlmodelc"
        ) {
            return try GPAElementDetector(compiledModelURL: bundledURL)
        }

        var candidates: [URL] = []
        if let override = environment["OMNIVIM_GPA_MODEL_PATH"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        if environment["OMNIVIM_ALLOW_DEVELOPMENT_MODEL_FALLBACK"] == "1" {
            candidates.append(developmentModelURL)
        }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return try GPAElementDetector(modelURL: candidate)
        }
        guard !candidates.isEmpty else {
            throw GPAElementDetectorError.bundledModelNotFound(name: "GPA_GUI_Detector")
        }
        throw GPAElementDetectorError.modelNotFound(
            searchedPaths: candidates.map(\.path)
        )
    }

    private static var developmentModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Detection
            .deletingLastPathComponent() // Vision
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // OmniVim
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Models/Generated/GPA_GUI_Detector.mlpackage")
    }
}
