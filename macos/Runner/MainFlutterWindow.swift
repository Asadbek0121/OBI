import Cocoa
import FlutterMacOS
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let channel = FlutterMethodChannel(name: "uz.asadbek.obi/ocr", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { (call, result) in
      if call.method == "performOCR" {
        if let args = call.arguments as? [String: Any],
           let imagePath = args["path"] as? String {
           self.performOCR(path: imagePath, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path is missing", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func performOCR(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      result(FlutterError(code: "IMAGE_ERROR", message: "Could not load image", details: nil))
      return
    }

    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest { (request, error) in
      guard let observations = request.results as? [VNRecognizedTextObservation], error == null else {
        result("")
        return
      }

      let recognizedStrings = observations.compactMap { observation in
        observation.topCandidates(1).first?.string
      }
      result(recognizedStrings.joined(separator: "\n"))
    }

    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "ru-RU"] // Support for English and Russian

    do {
      try requestHandler.perform([request])
    } catch {
      result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
    }
  }
}
