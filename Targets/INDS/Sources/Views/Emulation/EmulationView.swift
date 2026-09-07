import SwiftUI

struct EmulationView: View {
    let rom: ROMFile
    @State private var sessionTimer: Timer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NDSRomViewWrapper(rom: rom, onQuitToLibrary: { dismiss() })
            .ignoresSafeArea()
            // Full-immersion emulation screen, iGBA-style: no system nav bar
            // while playing. "Quit to Library" in the pause menu (or an edge
            // swipe-back) is the way out.
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                rom.recordingPlayStart()
                sessionTimer?.invalidate() // a double onAppear must not double-count
                sessionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    rom.incrementPlayTime(by: 60)
                }
            }
            .onDisappear {
                sessionTimer?.invalidate()
                sessionTimer = nil
            }
    }
}
