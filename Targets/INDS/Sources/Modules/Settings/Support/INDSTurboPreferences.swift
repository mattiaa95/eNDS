//
//  INDSTurboPreferences.swift
//  eNDS
//
//  Qué botones disparan solos mientras se mantienen pulsados. Es una
//  preferencia y no una propiedad de la distribución de controles: vale
//  igual para el overlay táctil, para un mando y para un teclado, y la
//  distribución solo conoce el primero.
//

import Foundation

enum INDSTurboPreferences {
    /// Solo los botones de acción. Turbo en la cruceta o en Start no hace
    /// nada útil y sí abre la puerta a menús parpadeando solos.
    static let eligible: [INDSButton] = [.A, .B, .X, .Y, .L, .R]

    private static let key = "eNDSTurboButtons"

    static var buttons: Set<INDSButton> {
        get {
            let raw = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
            return Set(raw.compactMap(INDSButton.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: key)
        }
    }

    static func isTurbo(_ button: INDSButton) -> Bool { buttons.contains(button) }

    static func setTurbo(_ on: Bool, for button: INDSButton) {
        var set = buttons
        if on { set.insert(button) } else { set.remove(button) }
        buttons = set
    }

    static var isAnyEnabled: Bool { !buttons.isEmpty }

    static func displayName(_ button: INDSButton) -> String {
        switch button {
        case .A: return "A"
        case .B: return "B"
        case .X: return "X"
        case .Y: return "Y"
        case .L: return "L"
        case .R: return "R"
        default: return ""
        }
    }
}
