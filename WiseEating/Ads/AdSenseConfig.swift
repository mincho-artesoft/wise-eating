import SwiftUI
import WebKit
import UIKit

// Този файл съдържа помощните класове само за Mac Catalyst
#if targetEnvironment(macCatalyst)

struct AdSenseConfig {
    // ⚠️ ТВОИТЕ ДАННИ ОТ ADSENSE
    static let publisherID = "ca-pub-3940256099942544" // Смени с твоя (напр. ca-pub-3759868960530173)
    
    // Трябва да създадеш "Display ad units" в AdSense конзолата и да вземеш ID-тата им
    static let bannerSlotID = "1234567890"       // Слот за банери
    static let interstitialSlotID = "0987654321" // Слот за цял екран
    
    // ⚠️ ВАЖНО: Твоят верифициран сайт. Без това рекламите няма да тръгнат!
    static let hostingURL = URL(string: "https://www.wiseeating.app")!
}

/// SwiftUI View за банери
struct AdSenseBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        
        let html = AdSenseHTMLGenerator.generate(slotID: AdSenseConfig.bannerSlotID, width: "100%", height: "100%")
        webView.loadHTMLString(html, baseURL: AdSenseConfig.hostingURL)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Helper за генериране на HTML кода
struct AdSenseHTMLGenerator {
    static func generate(slotID: String, width: String, height: String) -> String {
        return """
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { margin: 0; padding: 0; display: flex; justify-content: center; align-items: center; height: 100vh; background-color: transparent; }
            </style>
        </head>
        <body>
            <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=\(AdSenseConfig.publisherID)"
                 crossorigin="anonymous"></script>
            <ins class="adsbygoogle"
                 style="display:block; width:\(width); height:\(height);"
                 data-ad-client="\(AdSenseConfig.publisherID)"
                 data-ad-slot="\(slotID)"
                 data-ad-format="auto"
                 data-full-width-responsive="true"></ins>
            <script>
                 (adsbygoogle = window.adsbygoogle || []).push({});
            </script>
        </body>
        </html>
        """
    }
}

/// Controller за Full Screen реклами на Mac
class MacFullScreenAdViewController: UIViewController, WKNavigationDelegate {
    var onDismiss: (() -> Void)?
    private var webView: WKWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black.withAlphaComponent(0.9)
        
        // Close button
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("Затвори рекламата ⓧ", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)
        
        // WebView
        webView = WKWebView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            webView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            webView.widthAnchor.constraint(equalToConstant: 600),
            webView.heightAnchor.constraint(equalToConstant: 500)
        ])
        
        let html = AdSenseHTMLGenerator.generate(slotID: AdSenseConfig.interstitialSlotID, width: "600px", height: "500px")
        webView.loadHTMLString(html, baseURL: AdSenseConfig.hostingURL)
    }
    
    @objc func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
#endif
