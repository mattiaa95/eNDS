import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Records the install moment the 48h honeymoon is measured from,
        // and starts the transaction listener so offer-code / out-of-band
        // Pro grants activate without the user opening the paywall.
        INDSHoneymoon.recordFirstLaunchIfNeeded()
#if DEBUG
        // Swift no tiene inicializadores estáticos como el autochequeo del
        // loopback en C++, así que este se llama a mano. Aborta en Debug si
        // los umbrales del aviso de valoración se rompen — el fallo que
        // vigila es no preguntar nunca, que no se nota hasta que faltan las
        // valoraciones.
        INDSReviewPrompt.selfCheck()
        // Barrido de geometría bajo demanda (`-iNDSLayoutSweep`): valida los
        // layouts por defecto sobre tamaños de plegable/ventana que ningún
        // simulador actual tiene. Sin el launch-arg no hace nada.
        INDSLayoutSweep.runIfRequested()
        // Igual pero visual (`-iNDSVisualSweep`): renderiza la pantalla de
        // emulación a PNG en tamaños de plegable/iPad y sale.
        INDSVisualSweep.runIfRequested()
#endif
        EntitlementManager.shared.startTransactionListener()
        EntitlementManager.shared.refreshEntitlementsAsync()

        if let url = launchOptions?[.url] as? URL {
            Self.handleFileURL(url)
        }
        return true
    }

    /// Refreshes StoreKit entitlements so offer-code redemptions made while
    /// the app was backgrounded (e.g. in the App Store) activate Pro
    /// automatically on return.
    func applicationWillEnterForeground(_ application: UIApplication) {
        EntitlementManager.shared.refreshEntitlementsAsync()
    }

    /// Routes ONLY the external-display role to our scene delegate (AirPlay
    /// mirroring / HDMI → the TV shows the DS top screen, see
    /// INDSExternalDisplayController). Every other role falls through to a
    /// plain configuration so SwiftUI keeps owning the on-device scene.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = INDSExternalSceneDelegate.self
        }
        return configuration
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.isFileURL else { return false }
        Self.handleFileURL(url)
        return true
    }

    private static let supportedExternalExtensions: Set<String> = ["nds", "zip", "7z", "gz", "sav"]

    /// Routes a file opened externally ("Open in eNDS" from Files/Safari, or
    /// a plain double-tap on a `.nds`/`.zip`/`.7z`/`.sav`) through the same import
    /// dispatcher the in-app "+" picker uses.
    ///
    /// A duplicate `.nds` is replaced silently (worst case the user re-imports a
    /// game they already had). A duplicate `.sav` is NOT: it would overwrite the
    /// live battery save, so it goes through the same "Already Exists / Replace?"
    /// alert the in-app picker uses. Someone double-tapping a `.sav` in Files to
    /// see what it is must not lose their progress for it.
    @MainActor
    static func handleFileURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard supportedExternalExtensions.contains(ext) else {
            debugLog("Ignoring unsupported external file: \(url.lastPathComponent)")
            return
        }
        // SwiftUI's `onOpenURL` and `application(_:open:)` can both fire for
        // one "Open in eNDS"; two concurrent imports of the same URL would
        // race on the security scope and on the destination file.
        guard inFlight.insert(url).inserted else { return }

        let isSave = (ext == "sav")
        Task.detached(priority: .userInitiated) {
            await importExternal(url, isSave: isSave)
            await MainActor.run { _ = inFlight.remove(url) }
        }
    }

    @MainActor private static var inFlight: Set<URL> = []

    private static func importExternal(_ url: URL, isSave: Bool) async {
        do {
            let outcome = try ROMStorageManager.importAny(from: url, replaceExisting: !isSave)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .romImported,
                    object: nil,
                    userInfo: ["filenames": outcome.importedROMURLs.map { $0.lastPathComponent }]
                )
                if !outcome.failureMessages.isEmpty {
                    NotificationCenter.default.post(
                        name: .romImportFailed,
                        object: nil,
                        userInfo: ["message": outcome.failureMessages.joined(separator: "\n")]
                    )
                }
            }
        } catch ROMStorageError.duplicateFile {
            // Only reachable for .sav (ROMs import with replaceExisting: true).
            // Stage a copy in tmp: the security-scoped grant on `url` is tied
            // to this open, and the user's answer can be seconds away.
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: staged)
            // `importAny` already closed its own scope; reopen it for the copy.
            let scoped = url.startAccessingSecurityScopedResource()
            let copied = (try? FileManager.default.copyItem(at: url, to: staged)) != nil
            if scoped { url.stopAccessingSecurityScopedResource() }
            guard copied else { return }
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .romImportNeedsReplaceConfirm,
                    object: nil,
                    userInfo: ["url": staged]
                )
            }
        } catch {
            debugLog("External ROM import failed: \(error.localizedDescription)")
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .romImportFailed,
                    object: nil,
                    userInfo: ["message": error.localizedDescription]
                )
            }
        }
    }
}
