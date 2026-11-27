import Foundation

/// Switches for variants that are being tried next to the ones they replace.
/// Each is on unless turned off, with a launch argument (`-newOnboarding NO`)
/// or the same UserDefaults key, so the earlier variant stays one flag away.
enum FeatureFlags {
    /// The first-run flow in five screens (welcome, about you, height and
    /// weight, constitution, allergies) instead of the 13-step profile
    /// wizard. The calendar is asked for at the end, with the reason, and not
    /// at launch; the consent form for ads waits until a profile exists.
    static var newOnboarding: Bool { isOn("newOnboarding") }

    /// One screen with one recommended plan, shown after the person has used
    /// the app a little, instead of the four-tab plan list shown right after
    /// the profile is created.
    static var newPaywall: Bool { isOn("newPaywall") }

    /// Set once a profile exists. With the new onboarding the consent form
    /// for ads waits for it, so that it does not cover the first screen.
    static var firstRunFinished: Bool {
        get { UserDefaults.standard.bool(forKey: "firstRunFinished") }
        set { UserDefaults.standard.set(newValue, forKey: "firstRunFinished") }
    }

    static var adsMayPrepare: Bool { !newOnboarding || firstRunFinished }

    private static func isOn(_ key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}
