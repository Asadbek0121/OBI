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
      guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
        result("")
        return
      }

      // Sort results by vertical position (top to bottom) and then horizontal (left to right)
      let sortedObservations = observations.sorted { (obj1, obj2) -> Bool in
          let box1 = obj1.boundingBox
          let box2 = obj2.boundingBox
          
          // If they are on the same line (allowing some tolerance)
          if abs(box1.origin.y - box2.origin.y) < 0.015 {
              return box1.origin.x < box2.origin.x
          }
          return box1.origin.y > box2.origin.y
      }

      var resultText = ""
      var lastY: CGFloat = -1.0
      
      for observation in sortedObservations {
          guard let candidate = observation.topCandidates(1).first else { continue }
          let currentY = observation.boundingBox.origin.y
          
          if lastY != -1.0 && abs(lastY - currentY) > 0.015 {
              resultText += "\n"
          } else if !resultText.isEmpty {
              resultText += " "
          }
          
          resultText += candidate.string
          lastY = currentY
      }
      
      result(resultText)
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
