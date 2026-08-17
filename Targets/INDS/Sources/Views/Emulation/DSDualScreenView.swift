//
//  DSDualScreenView.swift
//  eNDS
//
//  New (no iGBA equivalent — GBA has a single screen). Owns the two DS
//  framebuffer views and positions them per `DSScreenLayoutMode`. Screen
//  *identity* is fixed: `topScreenView` always presents the DS top
//  framebuffer, `bottomScreenView` always presents the touch framebuffer —
//  only their on-screen position changes, so touch handling (attached once to
//  `bottomScreenView` by the view controller) never has to ask "which buffer
//  am I looking at right now".
//

import UIKit

final class DSDualScreenView: UIView {

    let topScreenView = UIImageView()
    let bottomScreenView = UIImageView()

    // One scanline overlay per screen, added as a sublayer so it moves/
    // resizes/animates in lockstep with its screen's own frame changes
    // below — see the `apply` closure in `applyLayout`, the single place
    // both a screen's frame and its overlay's frame are set.
    private let topScanlineLayer = DSDualScreenView.makeScanlineLayer()
    private let bottomScanlineLayer = DSDualScreenView.makeScanlineLayer()

    private var currentMode: DSScreenLayoutMode = .stacked
    private var currentSwap = false
    private var currentStretch = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        for screen in [topScreenView, bottomScreenView] {
            screen.backgroundColor = UIColor(white: 0.05, alpha: 1)
            // Square corners and no border: the DS panels are rectangular, and
            // a 14pt radius plus a 1pt inset stroke was clipping real emulated
            // pixels off all four corners of both screens for decoration.
            screen.clipsToBounds = true
            screen.contentMode = .scaleAspectFit
            screen.isUserInteractionEnabled = false
            addSubview(screen)
        }
        // Only the bottom (touch) screen ever receives gestures; attached by
        // the owning view controller, which also owns the coordinate mapping.
        bottomScreenView.isUserInteractionEnabled = true

        // With VoiceOver on, every touch becomes a VoiceOver gesture — so the
        // DS touch screen, which needs raw taps and drags at exact coordinates,
        // simply could not be used. `.allowsDirectInteraction` hands touches
        // straight through inside this view's frame, which is the only way a
        // stylus screen can work: no VoiceOver gesture can express "drag from
        // here to there on the game's own canvas".
        bottomScreenView.isAccessibilityElement = true
        bottomScreenView.accessibilityTraits = .allowsDirectInteraction
        bottomScreenView.accessibilityLabel = NSLocalizedString(
            "DS touch screen", comment: "VoiceOver label for the lower, touch-sensitive DS screen")
        bottomScreenView.accessibilityHint = NSLocalizedString(
            "Touches here go straight to the game, like a stylus on the real console.",
            comment: "VoiceOver hint explaining direct interaction on the DS touch screen")

        // Named but not interactive: it is the picture you are looking at.
        topScreenView.isAccessibilityElement = true
        topScreenView.accessibilityTraits = .image
        topScreenView.accessibilityLabel = NSLocalizedString(
            "DS top screen", comment: "VoiceOver label for the upper DS screen")

        topScreenView.layer.addSublayer(topScanlineLayer)
        bottomScreenView.layer.addSublayer(bottomScanlineLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: - Display filter

    /// Applies `filter` live to both screens. `.crisp` switches both layers'
    /// magnification to nearest-neighbor (pixel-perfect, no smoothing);
    /// `.scanlines` keeps the default smooth (linear) scaling underneath but
    /// shows the tiled horizontal-line overlay on top of each screen;
    /// `.smooth` is both layers' default and shows no overlay. Safe to call
    /// at any time, loaded ROM or not.
    func applyDisplayFilter(_ filter: NDSDisplayFilter) {
        let magnification: CALayerContentsFilter = filter == .crisp ? .nearest : .linear
        topScreenView.layer.magnificationFilter = magnification
        bottomScreenView.layer.magnificationFilter = magnification

        let showsScanlines = filter == .scanlines
        topScanlineLayer.isHidden = !showsScanlines
        bottomScanlineLayer.isHidden = !showsScanlines
    }

    /// A 1pt-wide, 2pt-tall tile — transparent on top, ~18% black on the
    /// bottom — repeated via `UIColor(patternImage:)` as a CALayer
    /// `backgroundColor`. Tiling this way reads as horizontal scanlines at
    /// any screen size without pre-baking a fixed-resolution overlay image.
    private static func makeScanlineLayer() -> CALayer {
        let tileSize = CGSize(width: 1, height: 2)
        let tile = UIGraphicsImageRenderer(size: tileSize).image { _ in
            UIColor.black.withAlphaComponent(0.18).setFill()
            UIRectFill(CGRect(x: 0, y: 1, width: 1, height: 1))
        }

        let layer = CALayer()
        layer.backgroundColor = UIColor(patternImage: tile).cgColor
        layer.isHidden = true
        return layer
    }

    /// Whether the bottom (touch) screen is currently on-screen at all.
    var isBottomScreenVisible: Bool { !bottomScreenView.isHidden }

    /// Set to false while a hardware gamepad is driving input (the on-screen
    /// overlay is hidden then) so the screens get the whole rect back.
    var reservesControlBand = true {
        didSet {
            guard reservesControlBand != oldValue else { return }
            applyLayout(mode: currentMode, swap: currentSwap, stretch: currentStretch, animated: true)
        }
    }

    /// Applies a screen arrangement, animating the transition when it changes
    /// (spec: "swap ... con transición suave"). Safe to call every layout
    /// pass — a no-op animation still runs but settles on the same frames.
    /// `stretch` mirrors Screens > "Fill screen (ignore aspect ratio)".
    func applyLayout(mode: DSScreenLayoutMode, swap: Bool, stretch: Bool = false, animated: Bool) {
        currentMode = mode
        currentSwap = swap
        currentStretch = stretch

        var content = bounds.inset(by: safeAreaInsets)
        // Portrait hands the bottom strip to the on-screen controls. Without
        // this the two stacked screens take ~79% of the height and the buttons
        // have to be crammed into what's left, landing on top of each other
        // and on the touch screen (see `INDSControlBand`). Landscape keeps the
        // full rect — there the controls overlay the screens' outer corners
        // translucently, and with a hardware gamepad there are no on-screen
        // controls to make room for at all.
        // `>=`, no `>`: en un contenedor CUADRADO (un plegable a media
        // apertura, una ventana de iPadOS a mitad de drag) el resto del
        // sistema — controles, HUD, orientationClass — resuelve "portrait",
        // y si aquí no se reserva la franja los controles caen encima de la
        // pantalla táctil.
        var portraitBand = false
        if content.height >= content.width, reservesControlBand {
            // Idiom efectivo por ancho: en una ventana estrecha de iPad los
            // controles pasan a métricas de iPhone y la franja reservada
            // tiene que encoger con ellos, o queda un hueco muerto.
            let idiom = INDSControlBand.effectiveIdiom(for: content.size)
            content.size.height = max(1, content.height - INDSControlBand.height(for: idiom))
            portraitBand = true
        }
        var (topFrame, bottomFrame) = DSScreenGeometry.frames(mode: mode, swap: swap, stretch: stretch, in: content)

        // El par apilado nace anclado arriba (en un iPhone el sobrante ≈ la
        // franja y no se nota), pero en una ventana alta y estrecha (Split
        // View a 1/3) deja un agujero negro enorme entre la pantalla táctil
        // y los controles. Se centra el bloque en el espacio que queda sobre
        // la franja; en iPhones el desplazamiento es ~0-10pt.
        if portraitBand, mode == .stacked, let top = topFrame, let bottom = bottomFrame {
            let slack = content.maxY - max(top.maxY, bottom.maxY)
            if slack > 1 {
                topFrame = top.offsetBy(dx: 0, dy: slack / 2)
                bottomFrame = bottom.offsetBy(dx: 0, dy: slack / 2)
            }
        }

        let apply = {
            if let topFrame {
                self.topScreenView.isHidden = false
                self.topScreenView.frame = topFrame
            } else {
                self.topScreenView.isHidden = true
            }
            if let bottomFrame {
                self.bottomScreenView.isHidden = false
                self.bottomScreenView.frame = bottomFrame
            } else {
                self.bottomScreenView.isHidden = true
            }
            // Sublayers don't auto-follow their parent layer's bounds —
            // keep the scanline overlays sized to whatever their screen
            // just got resized to, every layout pass, regardless of
            // whether the .scanlines filter is even the active one right
            // now (cheap, and keeps `applyDisplayFilter` a pure show/hide).
            self.topScanlineLayer.frame = self.topScreenView.bounds
            self.bottomScanlineLayer.frame = self.bottomScreenView.bounds
        }

        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Bounds changed (rotation, size class change) — re-lay-out with the
        // same mode/swap/stretch the caller last requested, no animation.
        applyLayout(mode: currentMode, swap: currentSwap, stretch: currentStretch, animated: false)
    }
}
