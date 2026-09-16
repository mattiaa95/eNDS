import SwiftUI

extension Notification.Name {
    /// Posted when an emulation screen leaves the hierarchy, so the library
    /// re-reads play time, last-played and save-state state it shows per cell.
    static let emulationSessionEnded = Notification.Name("eNDSEmulationSessionEnded")
}

struct EmulationView: View {
    let rom: ROMFile
    @State private var sessionTimer: Timer?
    /// Balances `ROMStorageManager.markOpen`/`markClosed` across a double
    /// `onAppear` (see the timer below) so the ROM is never left registered
    /// as open after this screen is gone.
    @State private var isRegisteredOpen = false
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
                if !isRegisteredOpen {
                    ROMStorageManager.markOpen(baseName: rom.baseName)
                    isRegisteredOpen = true
                }
                sessionTimer?.invalidate() // a double onAppear must not double-count
                sessionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    rom.incrementPlayTime(by: 60)
                }
            }
            .onDisappear {
                sessionTimer?.invalidate()
                sessionTimer = nil
                if isRegisteredOpen {
                    ROMStorageManager.markClosed(baseName: rom.baseName)
                    isRegisteredOpen = false
                }
                NotificationCenter.default.post(name: .emulationSessionEnded, object: nil)
            }
    }
}
