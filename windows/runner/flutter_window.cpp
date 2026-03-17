#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/base.h>

using namespace winrt;
using namespace Windows::Media::Ocr;
using namespace Windows::Storage;
using namespace Windows::Storage::Streams;
using namespace Windows::Graphics::Imaging;

#include "flutter_window.h"
#include <optional>
#include "flutter/generated_plugin_registrant.h"

// Forward declaration
void HandleOCRRequest(const flutter::MethodCall<flutter::EncodableValue>& method_call,
                     std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
    // Initialize WinRT for OCR
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
}

FlutterWindow::~FlutterWindow() {
    winrt::uninit_apartment();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  // Native OCR Channel Setup for Windows
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "uz.asadbek.obi/ocr",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() == "performOCR") {
          HandleOCRRequest(call, std::move(result));
        } else {
          result->NotImplemented();
        }
      });

  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

// Windows Native OCR Implementation using built-in OS features
void HandleOCRRequest(const flutter::MethodCall<flutter::EncodableValue>& method_call,
                     std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
        result->Error("INVALID_ARGS", "Arguments missing");
        return;
    }

    auto path_it = arguments->find(flutter::EncodableValue("path"));
    if (path_it == arguments->end()) {
        result->Error("INVALID_ARGS", "Path missing");
        return;
    }

    std::string path = std::get<std::string>(path_it->second);
    std::wstring wpath(path.begin(), path.end());

    // Run OCR in a background task
    try {
        auto file = StorageFile::GetFileFromPathAsync(wpath).get();
        auto stream = file.OpenAsync(FileAccessMode::Read).get();
        auto decoder = BitmapDecoder::CreateAsync(stream).get();
        auto bitmap = decoder.GetSoftwareBitmapAsync().get();

        // Use English or Russian engines if available, default to system
        OcrEngine engine = OcrEngine::TryCreateFromUserProfileLanguages();
        auto ocrResult = engine.RecognizeAsync(bitmap).get();

        std::wstring text = L"";
        for (auto const& line : ocrResult.Lines()) {
            text += line.Text() + L"\n";
        }

        // Convert wstring back to string for Flutter
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, &text[0], (int)text.size(), NULL, 0, NULL, NULL);
        std::string strTo(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, &text[0], (int)text.size(), &strTo[0], size_needed, NULL, NULL);

        result->Success(flutter::EncodableValue(strTo));
    } catch (const winrt::hresult_error& ex) {
        std::wstring msg = ex.message().c_str();
        int size_needed = WideCharToMultiByte(CP_UTF8, 0, &msg[0], (int)msg.size(), NULL, 0, NULL, NULL);
        std::string strMsg(size_needed, 0);
        WideCharToMultiByte(CP_UTF8, 0, &msg[0], (int)msg.size(), &strMsg[0], size_needed, NULL, NULL);
        result->Error("OCR_ERROR", strMsg);
    } catch (...) {
        result->Error("OCR_ERROR", "Unknown native error during Windows OCR");
    }
}
