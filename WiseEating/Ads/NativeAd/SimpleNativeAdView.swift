import GoogleMobileAds
import UIKit

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
        label.numberOfLines = 2 // Позволяваме 2 реда, защото ширината намалява
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
    
    // ✅ ПРОМЯНА: MediaView заема по-голяма площ (за видео изискванията)
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
        
        self.iconView = iconImageView
        self.headlineView = headlineLabel
        self.bodyView = bodyLabel
        self.callToActionView = callToActionButton
        self.mediaView = mediaViewOutlet
        
        // MARK: - Layout Logic
        // Тъй като MediaView трябва да е поне 120x120, а височината на реда е 140,
        // най-добре е MediaView да е квадрат вдясно, а текстът да е вляво.
        
        NSLayoutConstraint.activate([
            // 1. MediaView (Дясно) - Фиксиран размер 120x120 за да махнем warning-а
            mediaViewOutlet.centerYAnchor.constraint(equalTo: centerYAnchor),
            mediaViewOutlet.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            mediaViewOutlet.widthAnchor.constraint(equalToConstant: 120),
            mediaViewOutlet.heightAnchor.constraint(equalToConstant: 120),
            
            // 2. Икона (Горе Ляво)
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconImageView.widthAnchor.constraint(equalToConstant: 40),
            iconImageView.heightAnchor.constraint(equalToConstant: 40),
            
            // 3. Заглавие (Вдясно от иконата, Вляво от MediaView)
            headlineLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            headlineLabel.topAnchor.constraint(equalTo: iconImageView.topAnchor),
            // Важно: Закотвяме го за mediaView, не за края на екрана
            headlineLabel.trailingAnchor.constraint(equalTo: mediaViewOutlet.leadingAnchor, constant: -8),
            
            // 4. Ad Badge (Под иконата)
            adBadgeLabel.leadingAnchor.constraint(equalTo: iconImageView.leadingAnchor),
            adBadgeLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            adBadgeLabel.widthAnchor.constraint(equalToConstant: 22),
            adBadgeLabel.heightAnchor.constraint(equalToConstant: 14),
            
            // 5. Body (Под заглавието, вляво от MediaView)
            bodyLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),
            bodyLabel.trailingAnchor.constraint(equalTo: mediaViewOutlet.leadingAnchor, constant: -8),
            
            // 6. Бутон (Долу Ляво, под Body)
            callToActionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            callToActionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            // Бутонът стига до медията, но не я застъпва
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
        
        // Зареждане на медията
        mediaView?.mediaContent = nativeAd.mediaContent
        // Показваме MediaView, ако има съдържание
        mediaView?.isHidden = false
    }
}
