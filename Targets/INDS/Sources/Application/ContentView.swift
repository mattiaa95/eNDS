import SwiftUI

struct ContentView: View {
    @State private var importErrorMessage: String?
    @State private var showSplash = true
    @ObservedObject private var appearance = INDSAppearanceStore.shared

    var body: some View {
        ZStack {
            ROMListView()
                .tint(appearance.accentColor)
                // .tint alone doesn't feed `Color.accentColor` reads
                // (Welcome/paywall backgrounds use it) — the deprecated
                // modifier is still the only way to set that from code.
                .accentColor(appearance.accentColor)
                .alert("Import Failed", isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { importErrorMessage = nil }
                } message: {
                    // `verbatim:` on purpose: the message is a runtime string
                    // that is already localized where it is produced; only the
                    // fallback is a literal, so it gets localized here.
                    Text(verbatim: importErrorMessage
                         ?? NSLocalizedString("The file could not be imported.", comment: "Import failure alert: fallback when the error carries no message"))
                }
                .onReceive(NotificationCenter.default.publisher(for: .romImportFailed)) { notification in
                    importErrorMessage = notification.userInfo?["message"] as? String
                        ?? NSLocalizedString("The file could not be imported.", comment: "Import failure alert: fallback when the error carries no message")
                }

            // Shown on every launch, like iGBA's own splash — fades itself
            // out internally, then this just removes it from the ZStack.
            if showSplash {
                SplashScreenView {
                    NotificationCenter.default.post(name: .splashDidComplete, object: nil)
                    showSplash = false
                }
                .zIndex(1)
            }
        }
    }
}
