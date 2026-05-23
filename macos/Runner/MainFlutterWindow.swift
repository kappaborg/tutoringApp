import AppKit
import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let ocrRegistrar = flutterViewController.registrar(forPlugin: "OcrPlugin")
    OcrChannel.register(with: ocrRegistrar)

    super.awakeFromNib()
  }
}

// MARK: - Apple Vision OCR method channel (macOS)
//
// Mirrors ios/Runner/AppDelegate.swift's OcrChannel. Runs entirely on-device.
enum OcrChannel {
  static let channelName = "com.kappasutra.picturebook/ocr"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
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

  /// Returns each detected text observation along with its bounding box; see
  /// the iOS implementation for the schema. Used by the import pipeline to
  /// filter out scattered labels that came from inside the illustration.
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
