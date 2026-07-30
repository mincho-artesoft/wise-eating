import UIKit

// MARK: - Top-most view-controller helper
extension UIApplication {

    var topMostViewController: UIViewController? {
        // 1. Locate the key window (works for multi-scene apps as well)
        let keyWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }          // each scene…
            .flatMap { $0.windows }                       // …all of its windows
            .first(where: { $0.isKeyWindow })             // the key one
        
        // 2. Walk up the presentation stack
        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

// ✅ ДОБАВИ ТОВА НАЙ-ДОЛУ (извън extension UIApplication)
// Тази глобална функция се използва от Ad мениджърите
@MainActor
func keyWindowRootViewController() -> UIViewController? {
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController
}
