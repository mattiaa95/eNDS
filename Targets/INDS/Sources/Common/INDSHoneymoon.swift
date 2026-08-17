import Foundation

/// First-launch "honeymoon": for the first 48 hours after install, every
/// Pro-gated convenience (save-state slots 2–4, the scanlines filter,
/// custom backgrounds) is unlocked so new players experience the full
/// app before deciding on Pro. Gates re-lock by themselves when it ends —
/// the same anti-resurrect clamps that guard an expired Pro subscription
/// already handle per-game profiles recorded during the honeymoon.
enum INDSHoneymoon {
    private static let firstLaunchDateKey = "eNDSFirstLaunchDate"
    private static let duration: TimeInterval = 48 * 60 * 60

    /// Called once from `AppDelegate.didFinishLaunching` — records the
    /// install moment the window is measured from.
    static func recordFirstLaunchIfNeeded() {
        if UserDefaults.standard.object(forKey: firstLaunchDateKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchDateKey)
        }
    }

    /// Cuándo se instaló. Lo lee `INDSReviewPrompt` en vez de llevar su propia
    /// cuenta: ya hay una fecha de instalación fiable y dos serían dos que se
    /// desincronizan en cuanto alguien toque una.
    static var firstLaunchDate: Date? {
        UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date
    }

    /// Whole hours left in the window, rounded up; nil once it is over.
    /// Drives the paywall's courtesy notice — the gates themselves only
    /// ever ask `isActive`.
    static var remainingHours: Int? {
        guard let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date else {
            return 48
        }
        let left = duration - Date().timeIntervalSince(firstLaunch)
        return left > 0 ? Int((left / 3600).rounded(.up)) : nil
    }

    static var isActive: Bool {
        guard let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchDateKey) as? Date else {
            // Not recorded yet (first frames of the very first launch) —
            // that IS the honeymoon.
            return true
        }
        return Date().timeIntervalSince(firstLaunch) < duration
    }
}
