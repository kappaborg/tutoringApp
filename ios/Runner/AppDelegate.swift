import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OcrPlugin") {
      OcrChannel.register(with: registrar)
    }
  }
}

// MARK: - Apple Vision OCR method channel
//
// Channel: "com.kappasutra.picturebook/ocr"
// Method:  "recognizeText" with { imagePath: String, languages?: [String] }
// Returns: String of joined lines, or empty when no text was found.
// Runs entirely on-device — no network.
enum OcrChannel {
  static let channelName = "com.kappasutra.picturebook/ocr"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "recognizeTextBlocks" {
      handleBlocks(call: call, result: result)
      return
    }
    guard call.method == "recognizeText" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["imagePath"] as? String else {
      result(FlutterError(code: "bad_args", message: "imagePath is required", details: nil))
      return
    }
    let languages = (args["languages"] as? [String]) ?? ["en-US"]
    let url = URL(fileURLWithPath: imagePath)

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      result(FlutterError(code: "image_load_failed", message: "Could not load image at \(imagePath)", details: nil))
      return
    }

    let request = VNRecognizeTextRequest { req, err in
      if let err = err {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision_failed", message: err.localizedDescription, details: nil))
        }
        return
      }
      let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
      let lines: [String] = observations.compactMap { obs in
        obs.topCandidates(1).first?.string
      }
      DispatchQueue.main.async {
        result(lines.joined(separator: "\n"))
      }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages

    DispatchQueue.global(qos: .userInitiated).async {
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// Returns each detected text observation along with its bounding box, so
  /// the Dart side can cluster boxes into paragraphs and drop scattered
  /// labels that came from inside the illustration rather than from a
  /// typeset paragraph.
  ///
  /// Each entry: {"text": String, "x": Double, "y": Double, "width": Double,
  ///              "height": Double, "confidence": Double}
  /// All coords are normalised 0–1 with (0,0) at the TOP-LEFT (image space).
  static func handleBlocks(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["imagePath"] as? String else {
      result(FlutterError(code: "bad_args", message: "imagePath is required", details: nil))
      return
    }
    let languages = (args["languages"] as? [String]) ?? ["en-US"]
    let url = URL(fileURLWithPath: imagePath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      result(FlutterError(code: "image_load_failed", message: "Could not load image at \(imagePath)", details: nil))
      return
    }

    let request = VNRecognizeTextRequest { req, err in
      if let err = err {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision_failed", message: err.localizedDescription, details: nil))
        }
        return
      }
      let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
      let blocks: [[String: Any]] = observations.compactMap { obs in
        guard let top = obs.topCandidates(1).first else { return nil }
        // Vision uses bottom-left origin; convert to top-left for Dart.
        let box = obs.boundingBox
        let topY = 1.0 - box.maxY
        return [
          "text": top.string,
          "x": box.minX,
          "y": topY,
          "width": box.width,
          "height": box.height,
          "confidence": Double(top.confidence),
        ]
      }
      DispatchQueue.main.async { result(blocks) }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = languages

    DispatchQueue.global(qos: .userInitiated).async {
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
