import UIKit

// Зареждаме GoogleMobileAds само ако не сме на Mac
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// MARK: - 1. REAL IMPLEMENTATION (iOS Only)
#if !targetEnvironment(macCatalyst)

final class SimpleNativeAdView: NativeAdView {

    // MARK: - UI Elements
    private let iconImageView: UIImageView = {
        let img = UIImageView()
        img.contentMode = .scaleAspectFit
        img.layer.cornerRadius = 4
        img.clipsToBounds = true
        img.translatesAutoresizingMaskIntoConstraints = false
        return img
    }()
    
    private let headlineLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let callToActionButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = .systemBlue
        btn.layer.cornerRadius = 14
        btn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isUserInteractionEnabled = false
        return btn
    }()
    
    // MediaView заема по-голяма площ
    private let mediaViewOutlet: MediaView = {
        let v = MediaView()
        v.contentMode = .scaleAspectFill
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 8
        v.clipsToBounds = true
        return v
    }()
    
    private let adBadgeLabel: UILabel = {
        let label = UILabel()
        label.text = "Ad"
        label.font = UIFont.systemFont(ofSize: 9, weight: .bold)
        label.textColor = .white
        label.backgroundColor = .orange
        label.textAlignment = .center
        label.layer.cornerRadius = 2
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        self.backgroundColor = .secondarySystemBackground
        self.layer.cornerRadius = 12
        self.clipsToBounds = true
        
        addSubview(iconImageView)
        addSubview(headlineLabel)
        addSubview(adBadgeLabel)
        addSubview(bodyLabel)
        addSubview(callToActionButton)
        addSubview(mediaViewOutlet)
        
        // Свързване с GADNativeAdView properties
        self.iconView = iconImageView
        self.headlineView = headlineLabel
        self.bodyView = bodyLabel
        self.callToActionView = callToActionButton
        self.mediaView = mediaViewOutlet
        
        NSLayoutConstraint.activate([
            // 1. MediaView (Дясно)
            mediaViewOutlet.centerYAnchor.constraint(equalTo: centerYAnchor),
            mediaViewOutlet.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            mediaViewOutlet.widthAnchor.constraint(equalToConstant: 120),
            mediaViewOutlet.heightAnchor.constraint(equalToConstant: 120),
            
            // 2. Икона (Горе Ляво)
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            // 3. Заглавие
            headlineLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            headlineLabel.topAnchor.constraint(equalTo: iconImageView.topAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: mediaViewOutlet.leadingAnchor, constant: -8),
            
            // 4. Ad Badge
            adBadgeLabel.leadingAnchor.constraint(equalTo: iconImageView.leadingAnchor),
            adBadgeLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            adBadgeLabel.widthAnchor.constraint(equalToConstant: 22),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 14),
            
            // 5. Body
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            bodyLabel.trailingAnchor.constraint(equalTo: mediaViewOutlet.leadingAnchor, constant: -8),
            
            // 6. Бутон
            callToActionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            callToActionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            callToActionButton.trailingAnchor.constraint(equalTo: mediaViewOutlet.leadingAnchor, constant: -8),
            callToActionButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    func populate(with nativeAd: NativeAd) {
        self.nativeAd = nativeAd

        (headlineView as? UILabel)?.text = nativeAd.headline
        (bodyView as? UILabel)?.text = nativeAd.body
        bodyView?.isHidden = nativeAd.body == nil
        
        (callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        callToActionView?.isHidden = nativeAd.callToAction == nil
        
        if let icon = nativeAd.icon?.image {
            (iconView as? UIImageView)?.image = icon
            iconView?.isHidden = false
        } else {
            iconView?.isHidden = true
        }
        
        mediaView?.mediaContent = nativeAd.mediaContent
        mediaView?.isHidden = false
    }
}

#else

// MARK: - 2. MAC CATALYST STUB (Placeholder)
// Този клас съществува само за да не гърми компилацията на Mac, ако някой се опита да създаде инстанция.
// Реално той никога няма да се покаже, защото NativeAdContainerView ще покаже AdSenseBannerView.

final class SimpleNativeAdView: UIView {
    // Празен метод, който приема "нещо" (Any), защото NativeAd не съществува тук
    func populate(with nativeAd: Any) {
        // No-op
    }
}

#endif
