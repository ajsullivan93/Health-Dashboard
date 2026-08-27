import SwiftUI
import WebKit

@main
struct HealthDashboardApp: App {
  var body: some Scene { WindowGroup { DashboardWebView() } }
}

struct DashboardWebView: UIViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.userContentController.add(context.coordinator, name: "healthKitSync")
    let view = WKWebView(frame: .zero, configuration: config)
    context.coordinator.webView = view
    if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
      view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    return view
  }
  func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.sync() }

  final class Coordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    let healthKit = HealthKitSyncManager()
    override init() {
      super.init()
      NotificationCenter.default.addObserver(self, selector: #selector(active), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    @objc func active() { sync() }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      healthKit.requestAuthorizationAndSync(send)
    }
    func sync() { healthKit.syncIfAuthorized(send) }
    func send(_ result: Result<HealthKitSyncResult, Error>) {
      DispatchQueue.main.async {
        switch result {
        case .success(let sync):
          let json = String(data: (try? JSONEncoder().encode(sync.payload)) ?? Data(), encoding: .utf8) ?? "{}"
          self.webView?.evaluateJavaScript("window.handleHealthKitSync(" + json + ");")
        case .failure(let error):
          let text = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
          self.webView?.evaluateJavaScript("window.handleHealthKitStatus({message:'HealthKit sync error: " + text + "'});")
        }
      }
    }
  }
}
