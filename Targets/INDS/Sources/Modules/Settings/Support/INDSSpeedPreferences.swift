//
//  INDSSpeedPreferences.swift
//  eNDS
//
//  The speed ladder, in one place. Two different things live here and they
//  are deliberately not the same list:
//
//  · `speeds` is what the pause menu's slider offers. It is the same ladder
//    as the GBA app's, so somebody who plays both finds the same steps in
//    the same order instead of 0.5/1/2 here and 0.5/1/1.5/2/2.5/3 there.
//  · `fastForwardSpeed` is what the Fast Forward button runs at. It was a
//    flat 2x nobody could change: on a controller the Fast Forward hotkey
//    was the only way to fast forward, and there was no way to say how fast
//    it should go. Now the on-screen Speed button steps through the rates
//    and a controller's hold uses whichever one is stored here.
//

import Foundation

enum INDSSpeedPreferences {
    /// Pause-menu slider steps.
    static let speeds: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]

    /// Fast Forward rates. Not the slider's ladder: fast forward slower than
    /// 2x is what the slider is for, and 4x is the rate the GBA app has
    /// always used for this same button.
    static let fastForwardSpeeds: [Double] = [2.0, 3.0, 4.0]

    static let defaultFastForwardSpeed: Double = 4.0

    private static let fastForwardKey = "eNDSFastForwardSpeed"

    /// Shared by the on-screen Speed button and a controller's Fast Forward
    /// hold — picking a rate with one changes the other.
    static var fastForwardSpeed: Double {
        get {
            // 0 = never set. Any other off-ladder value comes from an older
            // build or an edited plist, so snap back rather than trust it:
            // the core clamps at 4x and a stored 8 would silently mean 4.
            let stored = UserDefaults.standard.double(forKey: fastForwardKey)
            return fastForwardSpeeds.contains(stored) ? stored : defaultFastForwardSpeed
        }
        set {
            guard fastForwardSpeeds.contains(newValue) else { return }
            UserDefaults.standard.set(newValue, forKey: fastForwardKey)
        }
    }

    /// The on-screen button's cycle: off → the stored rate → every faster
    /// one → off again. `nil` in means "currently off", `nil` out means
    /// "switch it off".
    static func nextFastForwardSpeed(after current: Double?) -> Double? {
        guard let current else { return fastForwardSpeed }
        guard let index = fastForwardSpeeds.firstIndex(of: current),
              index + 1 < fastForwardSpeeds.count else { return nil }
        return fastForwardSpeeds[index + 1]
    }

    /// "2x", "0.5x" — only the half steps spend a decimal place.
    static func label(_ speed: Double) -> String {
        speed.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fx", speed)
            : String(format: "%.1fx", speed)
    }
}
