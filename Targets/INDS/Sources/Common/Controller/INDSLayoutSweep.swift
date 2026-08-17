#if DEBUG
//
//  INDSLayoutSweep.swift
//  eNDS
//
//  Barrido de geometría por launch-arg `-iNDSLayoutSweep`: valida los layouts
//  por defecto y las pantallas DS sobre una matriz de tamaños de contenedor
//  arbitrarios — los candybar actuales, los aspectos casi cuadrados de un
//  iPhone plegable desplegado y los tamaños intermedios de una ventana
//  redimensionable de iPadOS (que un drag recorre TODOS). Ningún simulador
//  actual puede reproducir esos tamaños; la geometría es pura función del
//  contenedor, así que se valida directamente.
//
//  Es la misma invariante que `NDSControllerView.assertDefaultLayoutHasNoOverlaps`
//  (la clase de bug de v1.0(8): un solape de 1px = un pulgar dispara dos
//  botones), pero contra el espacio de tamaños completo en vez del único
//  device donde corre el build. Imprime un veredicto por caso y termina el
//  proceso: PASS todos → exit 0, cualquier FAIL → exit 1.
//

import UIKit

enum INDSLayoutSweep {

    /// Llamado desde `AppDelegate.didFinishLaunching` (solo DEBUG). Si el
    /// launch-arg no está, no hace nada.
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-iNDSLayoutSweep") else { return }

        // Anchos×altos en puntos. Cada tamaño se prueba tal cual y traspuesto,
        // con idiom .phone y .pad. `mustPass: false` = por debajo del mínimo
        // real de ventana (informativo, no rompe el barrido).
        let cases: [(size: CGSize, mustPass: Bool)] = [
            // Candybar actuales (plegado, pantalla exterior)
            (CGSize(width: 320, height: 568), true),
            (CGSize(width: 375, height: 667), true),
            (CGSize(width: 393, height: 852), true),
            (CGSize(width: 430, height: 932), true),
            (CGSize(width: 440, height: 956), true),
            // Plegable desplegado: aspectos 4:3-ish / casi cuadrados
            (CGSize(width: 600, height: 700), true),
            (CGSize(width: 640, height: 840), true),
            (CGSize(width: 700, height: 840), true),
            (CGSize(width: 717, height: 829), true),
            (CGSize(width: 768, height: 1024), true),
            (CGSize(width: 800, height: 900), true),
            // Cuadrados exactos (peor caso del umbral portrait/landscape)
            (CGSize(width: 500, height: 500), true),
            (CGSize(width: 700, height: 700), true),
            // Ventana iPadOS / Split View (el drag pasa por todos los intermedios)
            (CGSize(width: 320, height: 480), true),
            (CGSize(width: 400, height: 600), true),
            (CGSize(width: 507, height: 678), true),
            (CGSize(width: 639, height: 1024), true),
            (CGSize(width: 834, height: 1194), true),
            (CGSize(width: 1024, height: 768), true),
            (CGSize(width: 1032, height: 1376), true),
            // Por debajo de cualquier mínimo de ventana: solo informativo
            (CGSize(width: 280, height: 400), false),
            (CGSize(width: 320, height: 1000), false),
        ]

        var failures = 0
        var total = 0
        var report: [String] = []
        for (base, mustPass) in cases {
            for size in [base, CGSize(width: base.height, height: base.width)] {
                for idiom in [UIUserInterfaceIdiom.phone, .pad] {
                    total += 1
                    let problems = validate(containerSize: size, idiom: idiom)
                    let tag = "\(Int(size.width))x\(Int(size.height)) \(idiom == .pad ? "pad" : "phone")"
                    if problems.isEmpty {
                        report.append("SWEEP PASS \(tag)")
                    } else if mustPass {
                        failures += 1
                        for p in problems { report.append("SWEEP FAIL \(tag): \(p)") }
                    } else {
                        for p in problems { report.append("SWEEP INFO \(tag) (bajo mínimo de ventana): \(p)") }
                    }
                }
            }
        }
        report.append("SWEEP DONE \(total - failures)/\(total) casos correctos, \(failures) fallos")
        report.forEach { print($0) }
        // El stdout de un `simctl launch` no siempre llega: el fichero en el
        // contenedor es la vía fiable de leer el veredicto desde fuera.
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? report.joined(separator: "\n")
                .write(to: docs.appendingPathComponent("layout-sweep.txt"), atomically: true, encoding: .utf8)
        }
        exit(failures == 0 ? 0 : 1)
    }

    /// Los cuatro botones frontales forman rombo apretado a propósito;
    /// `buttonsForTouch` resuelve ese solape por centro más cercano. Mismo
    /// eximente que la aserción de producción.
    private static let faceCluster: Set<INDSControllerButtonID> = [.a, .b, .x, .y]

    private static func validate(containerSize size: CGSize, idiom: UIUserInterfaceIdiom) -> [String] {
        var problems: [String] = []
        let isPortrait = size.height >= size.width

        let layout = isPortrait
            ? INDSCustomControllerLayout.defaultPortrait(containerSize: size, idiom: idiom)
            : INDSCustomControllerLayout.defaultLandscape(containerSize: size, idiom: idiom)

        // Mismo conjunto que valida producción: visibles y no-chrome (el HUD
        // dibuja Menu/Layout/FF con su propia métrica).
        let frames: [(id: INDSControllerButtonID, frame: CGRect)] = layout.buttons
            .filter { $0.isVisible && !$0.id.isHUDChrome }
            .map { ($0.id, $0.clampedFrame(in: size, userInterfaceIdiom: idiom)) }
            .sorted { $0.0.rawValue < $1.0.rawValue }

        let container = CGRect(origin: .zero, size: size)
        for (id, frame) in frames {
            if frame.width < 1 || frame.height < 1 {
                problems.append("\(id.rawValue) con tamaño degenerado \(frame.size)")
            }
            if !container.contains(frame) {
                problems.append("\(id.rawValue) fuera del contenedor: \(frame)")
            }
        }
        for (index, lhs) in frames.enumerated() {
            for rhs in frames.dropFirst(index + 1) where lhs.frame.intersects(rhs.frame) {
                if faceCluster.contains(lhs.id), faceCluster.contains(rhs.id) { continue }
                problems.append("solape \(lhs.id.rawValue) \(lhs.frame) x \(rhs.id.rawValue) \(rhs.frame) -> \(lhs.frame.intersection(rhs.frame))")
            }
        }

        // Pantallas DS: en vertical la franja de controles se resta primero
        // (exactamente lo que hace DSDualScreenView con reservesControlBand).
        let mode: DSScreenLayoutMode = isPortrait ? .stacked : .sideBySide
        var screenBounds = container
        if isPortrait {
            // Mismo cálculo que DSDualScreenView: la franja usa el idiom
            // efectivo por ancho, no el del device.
            let bandIdiom = INDSControlBand.effectiveIdiom(for: size, device: idiom)
            screenBounds.size.height -= INDSControlBand.height(for: bandIdiom)
        }
        if screenBounds.height < 100 {
            problems.append("la franja de controles no deja sitio a las pantallas (quedan \(Int(screenBounds.height))pt)")
        } else {
            let (top, bottom) = DSScreenGeometry.frames(mode: mode, swap: false, in: screenBounds)
            for (name, rect) in [("top", top), ("bottom", bottom)] {
                guard let rect else {
                    problems.append("pantalla \(name) ausente en modo \(mode)")
                    continue
                }
                if rect.width < 1 || rect.height < 1 {
                    problems.append("pantalla \(name) degenerada: \(rect)")
                    continue
                }
                let aspect = rect.width / rect.height
                let expected = DSScreenGeometry.aspectWidth / DSScreenGeometry.aspectHeight
                if abs(aspect - expected) > 0.01 {
                    problems.append("pantalla \(name) pierde el 4:3: \(rect) (aspect \(aspect))")
                }
                if !screenBounds.insetBy(dx: -0.5, dy: -0.5).contains(rect) {
                    problems.append("pantalla \(name) invade la franja de controles: \(rect)")
                }
            }
        }

        return problems
    }
}
#endif
