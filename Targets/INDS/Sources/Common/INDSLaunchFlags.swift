import Foundation

/// Process-level launch flags. `screenshotHarness` drives the App Store
/// screenshot UITest runs: it keeps the app in its true "fresh device, no
/// controller" presentation, which the simulator can't reproduce naturally
/// (the host keyboard registers as a connected gamepad and would hide the
/// touch overlay in every capture).
enum INDSLaunchFlags {
    static let screenshotHarness =
        ProcessInfo.processInfo.arguments.contains("-eNDSScreenshotHarness")
}
