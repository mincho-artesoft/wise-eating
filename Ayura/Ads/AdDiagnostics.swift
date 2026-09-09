import Foundation
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
enum AdDiagnostics {
    static func failure(_ placement: String, _ error: Error) {
        let error = error as NSError
        print("[Ads] \(placement) failed: domain=\(error.domain), code=\(error.code), \(error.localizedDescription)")
        #if canImport(GoogleMobileAds)
        if let response = error.userInfo[GADErrorUserInfoKeyResponseInfo] as? ResponseInfo {
            print("[Ads] \(placement) response: \(response)")
        }
        #endif
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("[Ads] \(placement) underlying error: domain=\(underlying.domain), code=\(underlying.code), \(underlying.localizedDescription)")
        }
    }
}
