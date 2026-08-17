import Foundation

func debugLog(_ message: String) {
    #if DEBUG
    print("[eNDS] \(message)")
    #endif
}
