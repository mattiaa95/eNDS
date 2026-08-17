import XCTest

/// Screenshot harness v2 — capturas finales App Store (post feature-merge).
/// La app se lanza con -eNDSScreenshotHarness (sin dialogos del sistema, overlay táctil
/// forzado aunque haya "mando" (teclado del sim), sin toast Connected).
final class ScreenshotTests: XCTestCase {

    let outDir = "/tmp/inds-screenshots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    private var deviceSuffix: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    @discardableResult
    private func launchApp(welcomeSeen: Bool = true, extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-eNDSScreenshotHarness", "YES",
                               "-eNDSHasSeenWelcome", welcomeSeen ? "YES" : "NO"] + extraArgs
        app.launch()
        return app
    }

    private func shoot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(outDir)/\(name)-\(deviceSuffix).png", contents: png)
    }

    private func bootJamClown(_ app: XCUIApplication) {
        let pred = NSPredicate(format: "label CONTAINS[c] %@", "clown")
        let cell = app.staticTexts.matching(pred).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 8), "JamClown cell not found")
        cell.tap()
        sleep(14)
    }

    private func openSaveStateSheet(_ app: XCUIApplication) {
        for label in ["Save State", "Save States", "Save & Load"] {
            let row = app.buttons[label].firstMatch
            if row.waitForExistence(timeout: 2) { row.tap(); return }
            let txt = app.staticTexts[label].firstMatch
            if txt.waitForExistence(timeout: 1) { txt.tap(); return }
        }
    }

    private func openPauseMenu(_ app: XCUIApplication) {
        let pause = app.buttons["hud.pause"]
        if pause.waitForExistence(timeout: 4) {
            pause.tap()
        } else {
            // fallback: esquina superior izquierda del HUD
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.055)).tap()
        }
        sleep(2)
    }

    @MainActor
    func test01_Library() throws {
        _ = launchApp()
        sleep(4)
        shoot("library")
    }

    @MainActor
    func test02_Welcome() throws {
        let app = launchApp(welcomeSeen: false)
        sleep(4)
        shoot("welcome-1")
        app.swipeLeft(); sleep(1)
        app.swipeLeft(); sleep(1)
        shoot("welcome-3")
    }

    @MainActor
    func test03_HeroPortrait() throws {
        let app = launchApp()
        sleep(2)
        bootJamClown(app)
        shoot("hero-portrait")
    }

    @MainActor
    func test04_HeroLandscape() throws {
        let app = launchApp()
        sleep(2)
        bootJamClown(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        shoot("hero-landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    @MainActor
    func test05_PauseAndSaves() throws {
        let app = launchApp()
        sleep(2)
        bootJamClown(app)
        openPauseMenu(app)
        shoot("pause-menu")

        // Guarda de verdad en el slot 1 y vuelve a entrar, para que la hoja
        // enseñe una miniatura real en vez de cuatro filas "Empty". Es a la
        // vez la comprobación de que capturar → escribir → leer → pintar
        // funciona de punta a punta.
        openSaveStateSheet(app)
        let slot1 = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Slot 1")).firstMatch
        if slot1.waitForExistence(timeout: 4) { slot1.tap() }
        sleep(3)

        // Tras guardar, unas veces se queda el menú de pausa abierto y otras
        // se vuelve al juego. Si el menú sigue ahí, reabrirlo tapa la captura.
        if !app.buttons["Save State"].firstMatch.waitForExistence(timeout: 2) {
            openPauseMenu(app)
        }
        openSaveStateSheet(app)
        // la hoja sobre hoja tarda: con 2 s la captura sale a medio presentar
        sleep(5)
        shoot("save-states")
    }

    @MainActor
    func test06_Cheats() throws {
        let app = launchApp()
        sleep(2)
        bootJamClown(app)
        openPauseMenu(app)
        for label in ["Cheats", "Cheat Codes"] {
            let row = app.buttons[label].firstMatch
            if row.waitForExistence(timeout: 2) { row.tap(); break }
            let txt = app.staticTexts[label].firstMatch
            if txt.waitForExistence(timeout: 1) { txt.tap(); break }
        }
        sleep(5)
        shoot("cheats")
    }

    @MainActor
    func test07_LayoutEditor() throws {
        let app = launchApp()
        sleep(2)
        tapAny(app, labels: ["Settings", "gearshape"])
        sleep(1)
        tapAny(app, labels: ["Controls"])
        sleep(1)
        for label in ["Edit Layout", "Layout Editor", "Customize Layout", "Edit On-Screen Controls"] {
            let el = app.buttons[label].firstMatch
            if el.waitForExistence(timeout: 2) { el.tap(); break }
            let txt = app.staticTexts[label].firstMatch
            if txt.waitForExistence(timeout: 1) { txt.tap(); break }
        }
        sleep(2)
        shoot("layout-editor")
    }

    @MainActor
    func test08_Settings() throws {
        let app = launchApp()
        sleep(2)
        tapAny(app, labels: ["Settings", "gearshape"])
        sleep(2)
        shoot("settings")
    }

    @MainActor
    func test09_Paywall() throws {
        let app = launchApp()
        sleep(2)
        tapAny(app, labels: ["Settings", "gearshape"])
        sleep(1)
        tapAny(app, labels: ["eNDS PRO"])
        sleep(3)
        shoot("paywall")
    }

    @MainActor
    func test10_About() throws {
        let app = launchApp()
        sleep(2)
        tapAny(app, labels: ["Settings", "gearshape"])
        sleep(1)
        tapAny(app, labels: ["About"])
        sleep(1)
        app.swipeUp()
        sleep(1)
        shoot("about-bottom")
    }

    /// Long-press preview card over the library (ROMDetailView). Plays first
    /// so the card has the things that make it worth showing: a real gameplay
    /// thumbnail and a save state.
    @MainActor
    func test11_ROMPreview() throws {
        let warmup = launchApp()
        sleep(2)
        bootJamClown(warmup)
        warmup.terminate()
        sleep(2)

        let app = launchApp()
        sleep(4)
        let pred = NSPredicate(format: "label CONTAINS[c] %@", "clown")
        let matches = app.staticTexts.matching(pred)
        // The same title also appears in the "Continue Playing" row at the top,
        // which has no context menu — take the lowest match, i.e. the grid cell.
        var target: XCUIElement?
        for i in 0..<matches.count {
            let el = matches.element(boundBy: i)
            guard el.exists else { continue }
            if target == nil || el.frame.minY > target!.frame.minY { target = el }
        }
        let cell = try XCTUnwrap(target, "JamClown grid cell not found")
        cell.press(forDuration: 1.4)
        sleep(3)
        shoot("rom-preview")
    }

    /// Ajustes › Controles. No va a la ficha: es la página que más se mueve
    /// (turbo, hápticos, opacidad, mapeo) y una captura la revisa entera.
    @MainActor
    func test12_Controls() throws {
        let app = launchApp()
        sleep(2)
        tapAny(app, labels: ["Settings", "gearshape"])
        sleep(1)
        tapAny(app, labels: ["Controls"])
        sleep(2)
        app.swipeUp()
        sleep(1)
        shoot("controls")
    }

    private func tapAny(_ app: XCUIApplication, labels: [String]) {
        for label in labels {
            let b = app.buttons[label].firstMatch
            if b.waitForExistence(timeout: 3) { b.tap(); return }
            let t = app.staticTexts[label].firstMatch
            if t.waitForExistence(timeout: 1) { t.tap(); return }
        }
    }
}
