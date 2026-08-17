#if DEBUG
//
//  INDSVisualSweep.swift
//  eNDS
//
//  Hermano visual de `INDSLayoutSweep` (launch-arg `-iNDSVisualSweep`): en vez
//  de validar números, RENDERIZA la pantalla de emulación real —
//  `DSDualScreenView` + `NDSControllerView`, las mismas clases y la misma
//  geometría de producción — a PNG en tamaños que ningún simulador actual
//  tiene (iPhone plegable plegado/desplegado, ventanas de iPadOS, Split
//  View), para poder VER cómo queda el layout antes de que exista el
//  hardware. Escribe los PNG en `Documents/visual-sweep/` y sale.
//
//  Limitación asumida: se pinta con `layer.render(in:)` fuera de ventana, así
//  que los blurs de los pills del HUD no salen (el HUD ni se monta — Menu/
//  Layout/Speed los dibuja NDSHUDView). Lo que se juzga aquí es la
//  composición: pantallas, franja y botones.
//

import UIKit

enum INDSVisualSweep {

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-iNDSVisualSweep") else { return }

        // (tamaño en puntos, etiqueta, idiom que declararía ese hardware)
        let cases: [(CGSize, String, UIUserInterfaceIdiom)] = [
            (CGSize(width: 430, height: 932), "plegable-PLEGADO-vertical", .phone),
            (CGSize(width: 932, height: 430), "plegable-PLEGADO-horizontal", .phone),
            (CGSize(width: 717, height: 829), "plegable-ABIERTO-vertical", .phone),
            (CGSize(width: 829, height: 717), "plegable-ABIERTO-horizontal", .phone),
            (CGSize(width: 800, height: 800), "plegable-cuadrado", .phone),
            (CGSize(width: 1032, height: 1376), "iPad13-vertical", .pad),
            (CGSize(width: 1376, height: 1032), "iPad13-horizontal", .pad),
            (CGSize(width: 507, height: 1376), "iPad-SplitView-mitad", .pad),
            (CGSize(width: 375, height: 1112), "iPad-SplitView-tercio", .pad),
        ]

        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { exit(1) }
        let dir = docs.appendingPathComponent("visual-sweep", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (size, name, idiom) in cases {
            let image = render(size: size, idiom: idiom)
            let url = dir.appendingPathComponent("\(name)-\(Int(size.width))x\(Int(size.height)).png")
            try? image.pngData()?.write(to: url)
        }
        try? "done".write(to: dir.appendingPathComponent("DONE.txt"), atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Compone la pantalla de emulación con las vistas de producción y la
    /// pinta offscreen. El idiom se fuerza pasándoselo a las factories/frames
    /// directamente — `UIDevice.current` aquí es el del simulador que corre
    /// el harness, no el del hardware simulado.
    private static func render(size: CGSize, idiom: UIUserInterfaceIdiom) -> UIImage {
        let container = UIView(frame: CGRect(origin: .zero, size: size))
        container.backgroundColor = UIColor(white: 0.05, alpha: 1)

        let isPortrait = size.height >= size.width
        let mode: DSScreenLayoutMode = isPortrait ? .stacked : .sideBySide

        let dual = DSDualScreenView(frame: container.bounds)
        container.addSubview(dual)
        dual.topScreenView.image = testPattern(label: "TOP", base: UIColor(red: 0.55, green: 0.10, blue: 0.16, alpha: 1))
        dual.bottomScreenView.image = testPattern(label: "TOUCH", base: UIColor(red: 0.09, green: 0.32, blue: 0.36, alpha: 1))
        dual.applyLayout(mode: mode, swap: false, stretch: false, animated: false)

        // Overlay de controles con los defaults calculados para ESTE
        // contenedor y ESTE idiom (mismo camino que updateButtonFrames, con
        // el idiom inyectado en vez del de UIDevice).
        let layout = isPortrait
            ? INDSCustomControllerLayout.defaultPortrait(containerSize: size, idiom: idiom)
            : INDSCustomControllerLayout.defaultLandscape(containerSize: size, idiom: idiom)
        for entry in layout.buttons where entry.isVisible {
            let frame = entry.clampedFrame(in: size, userInterfaceIdiom: idiom)
            let view: UIView
            if entry.id == .dpad {
                view = INDSDPadShapeView(frame: frame)
                view.alpha = 0.55
            } else if entry.id.isHUDChrome {
                // El HUD real dibuja pills con blur; aquí una cápsula plana
                // con la misma métrica para juzgar la composición.
                let label = UILabel(frame: frame)
                label.text = entry.id.defaultStyleLabel
                label.font = .systemFont(ofSize: 11, weight: .semibold)
                label.textAlignment = .center
                label.textColor = .white
                label.backgroundColor = UIColor(white: 0.25, alpha: 0.75)
                label.layer.cornerRadius = 10
                label.clipsToBounds = true
                view = label
            } else {
                let styled = INDSStyledButtonView(buttonID: entry.id,
                                                  style: entry.style ?? .defaultStyle(for: entry.id))
                styled.frame = frame
                styled.updateForSize(frame.size)
                styled.alpha = 0.55
                view = styled
            }
            view.frame = frame
            container.addSubview(view)
        }

        container.setNeedsLayout()
        container.layoutIfNeeded()
        // layoutSubviews de DSDualScreenView re-aplica el modo con los bounds
        // definitivos; una segunda pasada explícita evita quedarnos con el
        // frame de antes del layout.
        dual.applyLayout(mode: mode, swap: false, stretch: false, animated: false)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            container.layer.render(in: ctx.cgContext)
        }
    }

    /// Un framebuffer DS de mentira (256×192): color base, rejilla, marco y
    /// etiqueta grande — suficiente para ver dónde cae cada pantalla, si se
    /// respeta el 4:3 y cuánto ocupa.
    private static func testPattern(label: String, base: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 192)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            base.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 1, alpha: 0.12).setStroke()
            let path = UIBezierPath()
            for x in stride(from: 0, through: 256, by: 32) {
                path.move(to: CGPoint(x: CGFloat(x), y: 0)); path.addLine(to: CGPoint(x: CGFloat(x), y: 192))
            }
            for y in stride(from: 0, through: 192, by: 32) {
                path.move(to: CGPoint(x: 0, y: CGFloat(y))); path.addLine(to: CGPoint(x: 256, y: CGFloat(y)))
            }
            path.stroke()
            UIColor.white.withAlphaComponent(0.9).setStroke()
            let border = UIBezierPath(rect: CGRect(x: 1, y: 1, width: 254, height: 190))
            border.lineWidth = 2
            border.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]
            let text = NSAttributedString(string: label, attributes: attrs)
            let bounds = text.boundingRect(with: size, options: [], context: nil)
            text.draw(at: CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
        }
    }
}
#endif
