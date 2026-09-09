import UIKit

private struct SpotCheckFood {
    let id: Int
    let frameIndex: Int
    let name: String
}

@main
final class FIX1VideoSpotCheckApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = SpotCheckViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

private final class SpotCheckViewController: UIViewController {
    private let foods = [
        SpotCheckFood(
            id: 90,
            frameIndex: 11_194,
            name: "Hot chocolate / cocoa, made with whole or reduced fat (2%) milk"
        ),
        SpotCheckFood(
            id: 91,
            frameIndex: 11_651,
            name: "Hot chocolate / cocoa, made with lowfat (1%) or fat free (skim) milk"
        ),
        SpotCheckFood(
            id: 99,
            frameIndex: 11_972,
            name: "Hot chocolate / cocoa, dry mix, made with whole or reduced fat (2%) milk"
        ),
        SpotCheckFood(
            id: 100,
            frameIndex: 11_762,
            name: "Hot chocolate / cocoa, dry mix, made with lowfat (1%) or fat free (skim) milk"
        ),
        SpotCheckFood(
            id: 104,
            frameIndex: 12_514,
            name: "Hot chocolate / cocoa, dry mix, reduced sugar, made with whole or reduced fat (2%) milk"
        ),
        SpotCheckFood(
            id: 6_148,
            frameIndex: 11_125,
            name: "Beef, short loin, porterhouse steak, separable lean only, trimmed to 1/8\" fat, choice, cooked, grilled"
        ),
        SpotCheckFood(
            id: 6_149,
            frameIndex: 2_840,
            name: "Beef, short loin, t-bone steak, bone-in, separable lean only, trimmed to 1/8\" fat, choice, raw"
        ),
        SpotCheckFood(
            id: 6_150,
            frameIndex: 436,
            name: "Beef, short loin, t-bone steak, bone-in, separable lean only, trimmed to 1/8\" fat, choice, cooked, grilled"
        ),
        SpotCheckFood(
            id: 6_167,
            frameIndex: 10_943,
            name: "Beef, short loin, porterhouse steak, separable lean only,  trimmed to 1/8\" fat, all grades, cooked, grilled"
        ),
        SpotCheckFood(
            id: 6_170,
            frameIndex: 12_128,
            name: "Beef, short loin, porterhouse steak, separable lean only, trimmed to 1/8\" fat, select, raw"
        ),
    ]

    private let summaryLabel = UILabel()
    private var imageViews: [UIImageView] = []
    private var statusLabels: [UILabel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        summaryLabel.font = .boldSystemFont(ofSize: 18)
        summaryLabel.text = "ID-key device check: loading 10 visible + 200 sampled frames…"
        summaryLabel.textAlignment = .center
        summaryLabel.numberOfLines = 2
        summaryLabel.accessibilityIdentifier = "fix1-summary"

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 6
        grid.distribution = .fillEqually

        for rowStart in stride(from: 0, to: foods.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
            row.addArrangedSubview(card(for: foods[rowStart]))
            row.addArrangedSubview(card(for: foods[rowStart + 1]))
            grid.addArrangedSubview(row)
        }

        let stack = UIStackView(arrangedSubviews: [summaryLabel, grid])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            summaryLabel.heightAnchor.constraint(equalToConstant: 44),
        ])

        loadFrames()
    }

    private func card(for food: SpotCheckFood) -> UIView {
        let imageView = UIImageView()
        imageView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 7
        imageView.accessibilityIdentifier = "fix1-image-\(food.id)"
        imageViews.append(imageView)

        let statusLabel = UILabel()
        statusLabel.font = .boldSystemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = "WAIT · ID \(food.id) · frame \(food.frameIndex)"
        statusLabels.append(statusLabel)

        let nameLabel = UILabel()
        nameLabel.font = .systemFont(ofSize: 9)
        nameLabel.numberOfLines = 2
        nameLabel.text = food.name

        let labels = UIStackView(arrangedSubviews: [statusLabel, nameLabel])
        labels.axis = .vertical
        labels.spacing = 1

        let card = UIStackView(arrangedSubviews: [imageView, labels])
        card.axis = .vertical
        card.spacing = 3
        imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        return card
    }

    private func loadFrames() {
        DispatchQueue.global(qos: .userInitiated).async { [foods] in
            let images = foods.map {
                FoodVideoSource.shared.getFrame(id: $0.id, variant: "144")
            }
            let available = FoodVideoSource.shared.availableFoodIDs
            let sampledIDs = (0..<200).map { position in
                available[position * (available.count - 1) / 199]
            }
            let sampledImages = sampledIDs.map {
                FoodVideoSource.shared.getFrame(id: $0, variant: "144")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var loaded = 0
                for (index, image) in images.enumerated() {
                    imageViews[index].image = image
                    if image != nil {
                        loaded += 1
                        statusLabels[index].text = "PASS · ID \(foods[index].id) · frame \(foods[index].frameIndex)"
                        statusLabels[index].textColor = .systemGreen
                    } else {
                        statusLabels[index].text = "FAIL · ID \(foods[index].id)"
                        statusLabels[index].textColor = .systemRed
                    }
                }
                let sampledLoaded = sampledImages.compactMap { $0 }.count
                summaryLabel.text = (
                    "ID-key device check: \(loaded)/\(foods.count) visible; "
                    + "\(sampledLoaded)/\(sampledIDs.count) sampled"
                )
                summaryLabel.textColor = (
                    loaded == foods.count && sampledLoaded == sampledIDs.count
                ) ? .systemGreen : .systemRed
            }
        }
    }
}
