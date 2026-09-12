//
//  DSScreenLayout.swift
//  eNDS
//
//  New (no iGBA equivalent — GBA has a single screen). Defines how the two DS
//  framebuffers (top = display only, bottom = touch) are arranged on screen,
//  plus persistence for the per-orientation mode and the swap flag.
//

import Foundation
import UIKit

/// Screen arrangement mode. Persisted separately per orientation class so a
/// user can e.g. keep `.stacked` in portrait but `.sideBySide` in landscape.
enum DSScreenLayoutMode: String, CaseIterable, Codable {
    case stacked
    case sideBySide
    case topOnly
    case bottomOnly

    var displayName: String {
        switch self {
        case .stacked:    return NSLocalizedString("Stacked", comment: "DS screen layout: both screens stacked vertically")
        case .sideBySide: return NSLocalizedString("Side by Side", comment: "DS screen layout: both screens side by side")
        case .topOnly:    return NSLocalizedString("Top Screen Only", comment: "DS screen layout: only the top screen")
        case .bottomOnly: return NSLocalizedString("Bottom Screen Only", comment: "DS screen layout: only the bottom/touch screen")
        }
    }

    var sfSymbolName: String {
        switch self {
        // Both from the `split` family, and both verified to exist:
        // "rectangle.grid.2x1.fill" is NOT a real SF Symbol, so
        // `UIImage(systemName:)` returned nil and the HUD's Layout button lost
        // its icon entirely in side-by-side — i.e. in landscape, by default.
        case .stacked:    return "rectangle.split.1x2.fill"
        case .sideBySide: return "rectangle.split.2x1.fill"
        case .topOnly:    return "square.tophalf.filled"
        case .bottomOnly: return "square.bottomhalf.filled"
        }
    }

    /// Whether the bottom (touch-capable) DS screen is visible at all in this mode.
    var showsBottomScreen: Bool { self != .topOnly }

    var next: DSScreenLayoutMode {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

enum DSScreenOrientationClass {
    case portrait
    case landscape
}

/// UserDefaults-backed persistence for the active screen layout. Keys are
/// stable and documented here so any future settings screen can read/write
/// them without going through this type.
enum DSScreenLayoutPreferences {
    private static let portraitKey = "eNDSScreenLayoutPortrait"
    private static let landscapeKey = "eNDSScreenLayoutLandscape"
    private static let swapKey = "eNDSScreenSwap"
    private static let stretchKey = "eNDSStretchScreens"

    static func mode(for orientationClass: DSScreenOrientationClass, containerSize: CGSize? = nil) -> DSScreenLayoutMode {
        if let saved = savedMode(for: orientationClass) { return saved }
        let consoleFits = containerSize.flatMap { DSConsoleLayout(in: $0) } != nil
        return orientationClass == .portrait || consoleFits ? .stacked : .sideBySide
    }

    /// nil is Automatic; explicit per-orientation choices keep their old keys.
    static func savedMode(for orientationClass: DSScreenOrientationClass) -> DSScreenLayoutMode? {
        let key = orientationClass == .portrait ? portraitKey : landscapeKey
        return UserDefaults.standard.string(forKey: key).flatMap(DSScreenLayoutMode.init(rawValue:))
    }

    static func setMode(_ mode: DSScreenLayoutMode?, for orientationClass: DSScreenOrientationClass) {
        let key = orientationClass == .portrait ? portraitKey : landscapeKey
        UserDefaults.standard.set(mode?.rawValue, forKey: key)
    }

    /// Advances and persists the mode for `orientationClass`, returning the new value.
    @discardableResult
    static func cycleMode(for orientationClass: DSScreenOrientationClass, containerSize: CGSize? = nil) -> DSScreenLayoutMode {
        let next = mode(for: orientationClass, containerSize: containerSize).next
        setMode(next, for: orientationClass)
        return next
    }

    static var swapEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: swapKey) }
        set { UserDefaults.standard.set(newValue, forKey: swapKey) }
    }

    /// "Fill screen (ignore aspect ratio)" — default OFF (today's always-4:3
    /// behavior).
    static var stretchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: stretchKey) }
        set { UserDefaults.standard.set(newValue, forKey: stretchKey) }
    }
}

/// A DS-shaped arrangement when two native-resolution panels and both thumb
/// clusters fit. These are content measurements, not device or hinge metrics.
struct DSConsoleLayout {
    let top: CGRect
    let bottom: CGRect
    let controls: INDSControllerLayout

    static func current(in size: CGSize, mode: DSScreenLayoutMode, stretch: Bool = false) -> DSConsoleLayout? {
        guard mode == .stacked, !stretch,
              INDSControllerLayoutManager.shared.persistedLayout == nil,
              (UserDefaults.standard.object(forKey: "eNDSControllerScale") as? Double ?? 1) <= 1 else { return nil }
        return DSConsoleLayout(in: size)
    }

    init?(in size: CGSize) {
        let idiom = INDSControlBand.effectiveIdiom(for: size)
        let dpad = INDSControllerButtonID.dpad.baseSize(for: idiom)
        let shoulder = INDSControllerButtonID.l.baseSize(for: idiom)
        let start = INDSControllerButtonID.start.baseSize(for: idiom)
        let hud = INDSControllerButtonID.menu.baseSize(for: idiom)
        let radius = INDSControlBand.faceClusterRadius(for: idiom)
        let rail = max(dpad.width, 2 * radius) + 16
        let header = hud.height + 20
        let panelHeight = (size.height - header - 16) / 2
        let screenWidth = min(size.width - 2 * rail, panelHeight * 4 / 3)
        guard screenWidth >= 256,
              panelHeight >= shoulder.height + 12 + max(dpad.height, 2 * radius) + 12 + start.height else { return nil }

        let screenHeight = screenWidth * 3 / 4
        let lowerY = header + panelHeight + 16
        top = CGRect(x: (size.width - screenWidth) / 2,
                     y: header + (panelHeight - screenHeight) / 2,
                     width: screenWidth, height: screenHeight)
        bottom = top.offsetBy(dx: 0, dy: panelHeight + 16)
        let left = rail / 2
        let right = size.width - left
        let middle = lowerY + panelHeight / 2
        let spread = INDSControlBand.faceSpread(for: idiom)
        controls = INDSControllerLayout(buttons: INDSControllerLayout.entries(from: [
            .l: CGPoint(x: left, y: lowerY + shoulder.height / 2),
            .r: CGPoint(x: right, y: lowerY + shoulder.height / 2),
            .dpad: CGPoint(x: left, y: middle),
            .y: CGPoint(x: right - spread, y: middle),
            .a: CGPoint(x: right + spread, y: middle),
            .x: CGPoint(x: right, y: middle - spread),
            .b: CGPoint(x: right, y: middle + spread),
            .select: CGPoint(x: left, y: size.height - start.height / 2),
            .start: CGPoint(x: right, y: size.height - start.height / 2),
            .layout: CGPoint(x: size.width / 2 - hud.width - 12, y: header / 2),
            .menu: CGPoint(x: size.width / 2, y: header / 2),
            .fastForward: CGPoint(x: size.width / 2 + hud.width + 12, y: header / 2),
        ], in: size))
    }
}

/// Pure geometry: computes where the DS top/bottom screens sit for a given
/// mode inside a content rect. Screen *identity* never changes — the returned
/// `top` rect is always for the DS top framebuffer and `bottom` for the DS
/// touch framebuffer; `swap` only reorders their on-screen position in the
/// dual-screen modes (stacked/sideBySide). `topOnly`/`bottomOnly` always show
/// exactly the screen their name says, regardless of swap, so cycling the HUD
/// button never surprises the user about which physical screen they asked for.
enum DSScreenGeometry {
    static let aspectWidth: CGFloat = 256
    static let aspectHeight: CGFloat = 192
    /// The two DS panels sit flush against each other, like the real hinge
    /// line. A gap here is dead space that comes straight out of the screens'
    /// size — with a reserved control band below (`INDSControlBand`), every
    /// point matters.
    static let gap: CGFloat = 0

    /// `stretch` (Screens > "Fill screen") drops the 4:3 aspect-fit and
    /// instead gives each screen the *entire* rect its mode/slot would
    /// otherwise only be centered inside — same slot boundaries (gap,
    /// stacking/side-by-side split) either way, just no more letterboxing.
    static func frames(mode: DSScreenLayoutMode, swap: Bool, stretch: Bool = false, in bounds: CGRect) -> (top: CGRect?, bottom: CGRect?) {
        switch mode {
        case .topOnly:
            return (stretch ? bounds : fit(in: bounds), nil)
        case .bottomOnly:
            return (nil, stretch ? bounds : fit(in: bounds))
        case .stacked:
            let (first, second) = stretch ? stackedFillPair(in: bounds) : stackedPair(in: bounds)
            return swap ? (second, first) : (first, second)
        case .sideBySide:
            let (first, second) = stretch ? sideBySideFillPair(in: bounds) : sideBySidePair(in: bounds)
            return swap ? (second, first) : (first, second)
        }
    }

    /// Single 256:192 rect, aspect-fit and centered in `bounds`.
    private static func fit(in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / aspectWidth, bounds.height / aspectHeight)
        let w = aspectWidth * scale
        let h = aspectHeight * scale
        return CGRect(x: bounds.minX + (bounds.width - w) / 2,
                      y: bounds.minY + (bounds.height - h) / 2,
                      width: w, height: h)
    }

    /// Two equal 256:192 rects stacked vertically, top-anchored (per spec:
    /// "centradas arriba"), horizontally centered — leaves the remainder of
    /// `bounds` below free for controls on any phone-shaped screen.
    private static func stackedPair(in bounds: CGRect) -> (CGRect, CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return (.zero, .zero) }
        var screenW = bounds.width
        var screenH = screenW * aspectHeight / aspectWidth
        if screenH * 2 + gap > bounds.height {
            screenH = (bounds.height - gap) / 2
            screenW = screenH * aspectWidth / aspectHeight
        }
        let x = bounds.minX + (bounds.width - screenW) / 2
        let topY = bounds.minY
        let bottomY = topY + screenH + gap
        return (CGRect(x: x, y: topY, width: screenW, height: screenH),
                CGRect(x: x, y: bottomY, width: screenW, height: screenH))
    }

    /// Two equal 256:192 rects side by side, centered in `bounds`.
    private static func sideBySidePair(in bounds: CGRect) -> (CGRect, CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return (.zero, .zero) }
        var screenH = bounds.height
        var screenW = screenH * aspectWidth / aspectHeight
        if screenW * 2 + gap > bounds.width {
            screenW = (bounds.width - gap) / 2
            screenH = screenW * aspectHeight / aspectWidth
        }
        let y = bounds.minY + (bounds.height - screenH) / 2
        let leadingX = bounds.minX
        let trailingX = leadingX + screenW + gap
        return (CGRect(x: leadingX, y: y, width: screenW, height: screenH),
                CGRect(x: trailingX, y: y, width: screenW, height: screenH))
    }

    /// `stackedPair`'s stretch counterpart: same top-anchored split (full
    /// width, half the height minus the gap each) but without recomputing
    /// `screenW`/`screenH` from the 4:3 aspect ratio first — each screen
    /// simply fills its whole half.
    private static func stackedFillPair(in bounds: CGRect) -> (CGRect, CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return (.zero, .zero) }
        let screenH = (bounds.height - gap) / 2
        let topY = bounds.minY
        let bottomY = topY + screenH + gap
        return (CGRect(x: bounds.minX, y: topY, width: bounds.width, height: screenH),
                CGRect(x: bounds.minX, y: bottomY, width: bounds.width, height: screenH))
    }

    /// `sideBySidePair`'s stretch counterpart — full height, half the width
    /// minus the gap each.
    private static func sideBySideFillPair(in bounds: CGRect) -> (CGRect, CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return (.zero, .zero) }
        let screenW = (bounds.width - gap) / 2
        let leadingX = bounds.minX
        let trailingX = leadingX + screenW + gap
        return (CGRect(x: leadingX, y: bounds.minY, width: screenW, height: bounds.height),
                CGRect(x: trailingX, y: bounds.minY, width: screenW, height: bounds.height))
    }
}
