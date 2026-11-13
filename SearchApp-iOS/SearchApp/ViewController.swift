import UIKit
import WebKit
import LocalAuthentication
import Security

// MARK: - تقديم ملفات الواجهة عبر app://localhost/ (يحافظ على عمل IndexedDB)
final class AssetHandler: NSObject, WKURLSchemeHandler {
    private let base = Bundle.main.resourceURL!.appendingPathComponent("www").standardizedFileURL

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        var rel = url.path
        if rel.isEmpty || rel == "/" { rel = "/index.html" }
        let file = base.appendingPathComponent(String(rel.dropFirst())).standardizedFileURL

        guard file.path.hasPrefix(base.path),
              let data = try? Data(contentsOf: file) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(r); urlSchemeTask.didFinish(); return
        }
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime(file.pathExtension),
            "Content-Length": "\(data.count)",
            "Cache-Control": "no-cache"
        ])!
        urlSchemeTask.didReceive(r)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        default: return "application/octet-stream"
        }
    }
}

// يمنع حلقة الاحتفاظ بين WKUserContentController والـ ViewController
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

final class ViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {

    private var web: WKWebView!
    private var outHandle: FileHandle?
    private var outURL: URL?

    private let keychainService = "com.search.app.bio"
    private let keychainAccount = "bank_bio"

    // MARK: - دورة الحياة
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.933, green: 0.945, blue: 0.965, alpha: 1) // #eef1f6

        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(AssetHandler(), forURLScheme: "app")
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.add(WeakScriptHandler(self), name: "native")
        cfg.userContentController.addUserScript(
            WKUserScript(source: shimScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))

        web = WKWebView(frame: .zero, configuration: cfg)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.uiDelegate = self
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.minimumZoomScale = 1.0
        web.scrollView.maximumZoomScale = 1.0
        web.scrollView.bouncesZoom = false
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        view.addSubview(web)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: g.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: g.trailingAnchor)
        ])

        web.load(URLRequest(url: URL(string: "app://localhost/index.html")!))
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - الجسر: window.Native (نفس أسماء دوال أندرويد)
    private func bioAvailable() -> Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    private func shimScript() -> String {
        let avail = bioAvailable() ? "true" : "false"
        let has = (keychainRead() != nil) ? "true" : "false"
        return """
        (function(){
          var avail=\(avail), has=\(has);
          function P(o){window.webkit.messageHandlers.native.postMessage(o)}
          window.Native={
            begin:function(n){P({a:"begin",name:n});return true},
            chunk:function(b){P({a:"chunk",d:b});return true},
            end:function(){P({a:"end"});return "تطبيق الملفات ← بنك المعلومات"},
            bioAvailable:function(){return avail},
            bioHasSecret:function(){return has},
            bioAuth:function(m){P({a:"bioAuth",mode:m})},
            bioSave:function(s){has=true;P({a:"bioSave",s:s})},
            bioGet:function(){P({a:"bioGet"})},
            openUrl:function(u){P({a:"openUrl",u:u})}
          };
        })();
        """
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let a = m["a"] as? String else { return }
        switch a {
        case "begin":   beginFile(m["name"] as? String ?? "bank.pack")
        case "chunk":   if let d = m["d"] as? String { appendChunk(d) }
        case "end":     endFile()
        case "bioAuth": bioAuth(m["mode"] as? String ?? "verify")
        case "bioSave": if let s = m["s"] as? String { keychainWrite(s) }
        case "bioGet":  bioGet()
        case "openUrl":
            if let s = m["u"] as? String, let u = URL(string: s) { UIApplication.shared.open(u) }
        default: break
        }
    }

    private func js(_ code: String) {
        DispatchQueue.main.async { self.web.evaluateJavaScript(code, completionHandler: nil) }
    }

    // MARK: - حفظ ملف الحزمة (Documents ثم نافذة المشاركة / حفظ في الملفات)
    private func beginFile(_ name: String) {
        try? outHandle?.close()
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(safe)
        try? FileManager.default.removeItem(at: url)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        outHandle = try? FileHandle(forWritingTo: url)
        outURL = url
    }

    private func appendChunk(_ b64: String) {
        guard let h = outHandle, let d = Data(base64Encoded: b64) else { return }
        h.write(d)
    }

    private func endFile() {
        try? outHandle?.close()
        outHandle = nil
        guard let url = outURL else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        vc.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(vc, animated: true)
    }

    // MARK: - Face ID / Touch ID + Keychain
    private func bioAuth(_ mode: String) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "إلغاء"
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "تحقق بالبصمة أو الوجه") { ok, _ in
            if mode == "save" { self.js("onBioSave(\(ok))") }
            else { self.js("onBioResult(\(ok))") }
        }
    }

    private func bioGet() {
        let s = keychainRead() ?? ""
        let q = (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        js("onBioSecret(\(q))")
    }

    private func keychainWrite(_ secret: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func keychainRead() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: - نوافذ JavaScript (alert / confirm / prompt)
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "حسناً", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }

    // الروابط الخارجية (http/https) تُفتح في سفاري بدل داخل التطبيق
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           let u = navigationAction.request.url, u.scheme == "http" || u.scheme == "https" {
            UIApplication.shared.open(u)
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
}
