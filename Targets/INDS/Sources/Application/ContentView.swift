import SwiftUI

struct ContentView: View {
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
