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

        return observations.compactMap { observation in
            let label = observation.labels.first
            let confidence = label?.confidence ?? observation.confidence
            guard confidence >= minimumConfidence else { return nil }
            return GPAGUIElementDetection(
                normalizedFrame: observation.boundingBox,
                confidence: confidence,
                identifier: label?.identifier ?? "interactive"
            )
        }
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
        candidates.append(developmentModelURL)

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return try GPAElementDetector(modelURL: candidate)
        }
        throw GPAElementDetectorError.modelNotFound(
            searchedPaths: candidates.map(\.path)
        )
    }

    private static var developmentModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Vision
            .deletingLastPathComponent() // OmniVim
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Models/Generated/GPA_GUI_Detector.mlpackage")
    }
}
