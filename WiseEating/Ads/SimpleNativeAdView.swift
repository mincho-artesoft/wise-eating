import GoogleMobileAds
import UIKit

final class SimpleNativeAdView: NativeAdView {

    @IBOutlet weak var headlineLabel: UILabel!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var callToActionButton: UIButton!
    @IBOutlet weak var mediaViewOutlet: MediaView!

    override func awakeFromNib() {
        super.awakeFromNib()

        // важно: закачаме под-view-тата към супер класа, за да се регистрират коректно
        headlineView = headlineLabel
        iconView = iconImageView
        callToActionView = callToActionButton
        mediaView = mediaViewOutlet
    }

    func populate(with nativeAd: NativeAd) {
        self.nativeAd = nativeAd

        (headlineView as? UILabel)?.text = nativeAd.headline
        (iconView as? UIImageView)?.image = nativeAd.icon?.image
        (callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)

        mediaView?.mediaContent = nativeAd.mediaContent
    }
}
