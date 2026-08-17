//
//  INDSCrossPromo.swift
//  eNDS
//
//  Placeholder for a possible future "more from this developer" card.
//  DISABLED — no UI wired up yet; this is only the skeleton so an eventual
//  card has a single, obvious place to land. If it ever ships it will be a
//  small dismissible card, and nothing here talks to the network.
//

import Foundation

enum INDSCrossPromo {
    /// Master switch. Stays `false`; nothing reads it besides this skeleton.
    static let isEnabled = false

    /// Persisted "user dismissed the card" flag — read once `isEnabled`
    /// flips true and an actual card view exists to check it.
    private static let dismissedKey = "eNDSCrossPromoDismissed"

    static var wasDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }

    /// Whether the (not-yet-built) card should be shown right now.
    static var shouldShow: Bool {
        isEnabled && !wasDismissed
    }
}
