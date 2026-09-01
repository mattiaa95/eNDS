//
//  INDSGamepadManager.swift
//  eNDS
//
//  Ported and adapted from iGBA's ExternalController.m (GBA-Emu repo): reads
//  a physical game controller (GCController) and drives the engine through a
//  delegate, the same role `NDSControllerView` plays for the on-screen
//  overlay. Adaptations vs. iGBA:
//   - Only the first controller is supported (multiple simultaneous pads are
//     out of scope for this pass).
//   - Physical-button → DS-button/app-action resolution goes through
//     `INDSControllerMappingStore` (per-controller-model remapping) instead
//     of a single flat dictionary.
//   - D-pad AND left thumbstick both drive movement simultaneously (union of
//     both sources), matching Nintendo-layout defaults; ports
//     iGBA's dpad-plus-thumbstick pattern but merges them into one directions
//     set instead of only ever reading whichever changed last.
//
//  Button-position mapping ("layout Nintendo"): GameController normalizes
//  every gamepad (Xbox/PlayStation/MFi/Nintendo) to Xbox-style position
//  names — buttonA/B/X/Y always mean south/east/west/north regardless of
//  what's printed on the controller. Nintendo's own printed layout has B at
//  south, A at east, Y at west, X at north — the exact rotation applied
//  below — so a physical Nintendo pad's printed A/B/X/Y line up with the DS's
//  own A/B/X/Y, while an Xbox/PlayStation pad's SOUTH button (labelled A or
//  ✕) drives the DS's B (matching where B actually sits on a real DS).
//
//  Menu button: `controllerPausedHandler` (soft-deprecated by Apple in favor
//  of `buttonMenu.valueChangedHandler`, but kept here — same as iGBA — since
//  it already delivers exactly the single discrete "pause was pressed" event
//  this needs, with no press/release bookkeeping required) is NEVER
//  remappable, guaranteeing a way into the pause menu regardless of what the
//  user does to the rest of the mapping.
//

import GameController

/// Where a controller's physical elements actually live.
///
/// iOS only gives a controller an `extendedGamepad` when it fits that profile
/// exactly; anything it cannot classify has none. An 8BitDo FlipPad wired over
/// USB-C is one of those, and code that reads only `extendedGamepad` wires
/// nothing at all for it — the pad connects, the touch controls disappear, and
/// no button does anything. (Reported against iGBA, fixed there first; this is
/// the same bug and the same fix.)
///
/// So every element is resolved twice: the typed property first, so nothing
/// changes for the pads that already worked, then by name off
/// `physicalInputProfile`, which every controller has whatever class iOS picked
/// for it. Both the gameplay path and the mapping screen resolve through here,
/// so a row that lights up is a button the game will actually read.
enum INDSControllerElements {

    /// The physical inputs the mapping store knows, in display order.
    static let physicalKeys = ["A", "B", "X", "Y", "L1", "R1", "L2", "R2", "Options"]

    static func button(_ key: String, on controller: GCController) -> GCControllerButtonInput? {
        let gamepad = controller.extendedGamepad
        let profile = controller.physicalInputProfile

        switch key {
        case "A":       return gamepad?.buttonA       ?? profile.buttons[GCButtonElementName.a.rawValue]
        case "B":       return gamepad?.buttonB       ?? profile.buttons[GCButtonElementName.b.rawValue]
        case "X":       return gamepad?.buttonX       ?? profile.buttons[GCButtonElementName.x.rawValue]
        case "Y":       return gamepad?.buttonY       ?? profile.buttons[GCButtonElementName.y.rawValue]
        case "L1":      return gamepad?.leftShoulder  ?? profile.buttons[GCButtonElementName.leftShoulder.rawValue]
        case "R1":      return gamepad?.rightShoulder ?? profile.buttons[GCButtonElementName.rightShoulder.rawValue]
        case "L2":      return gamepad?.leftTrigger   ?? profile.buttons[GCButtonElementName.leftTrigger.rawValue]
        case "R2":      return gamepad?.rightTrigger  ?? profile.buttons[GCButtonElementName.rightTrigger.rawValue]
        case "Options": return gamepad?.buttonOptions ?? profile.buttons[GCButtonElementName.options.rawValue]
        default:        return nil
        }
    }

    /// Every button this controller actually has, paired with its mapping key.
    static func buttons(on controller: GCController) -> [(key: String, button: GCControllerButtonInput)] {
        physicalKeys.compactMap { key in
            button(key, on: controller).map { (key, $0) }
        }
    }

    static func directionPad(on controller: GCController) -> GCControllerDirectionPad? {
        controller.extendedGamepad?.dpad
            ?? controller.physicalInputProfile.dpads[GCDirectionPadElementName.directionPad.rawValue]
    }

    static func thumbstick(on controller: GCController) -> GCControllerDirectionPad? {
        if let stick = controller.extendedGamepad?.leftThumbstick { return stick }

        let profile = controller.physicalInputProfile
        if let stick = profile.dpads[GCDirectionPadElementName.leftThumbstick.rawValue] { return stick }

        // iOS 26 added a generic name for devices with a single stick and no
        // left/right distinction — the same devices that get no extendedGamepad.
        // It resolves to nil on a normal pad, so this costs those nothing.
        if #available(iOS 26.0, *) {
            return profile.dpads[GCDirectionPadElementName.thumbstick.rawValue]
        }
        return nil
    }

    /// What iOS reports for this controller, for the mapping screen to show.
    /// A pad whose buttons do nothing is otherwise a dead end for support.
    static func detectedNames(on controller: GCController) -> [String] {
        let profile = controller.physicalInputProfile
        return (Array(profile.buttons.keys) + Array(profile.dpads.keys)).sorted()
    }
}

protocol INDSGamepadManagerDelegate: AnyObject {
    func gamepadManager(_ manager: INDSGamepadManager, setButton button: INDSButton, pressed: Bool)
    func gamepadManager(_ manager: INDSGamepadManager, perform action: INDSControllerAppAction)
    func gamepadManager(_ manager: INDSGamepadManager, setFastForwardActive active: Bool)
    func gamepadManagerDidChangeConnection(_ manager: INDSGamepadManager, connected: Bool)
}

final class INDSGamepadManager {

    weak var delegate: INDSGamepadManagerDelegate?

    private(set) var current: GCController?

    /// How many of the current pad's inputs could be wired. A controller that
    /// drives nothing must not count as connected: hiding the on-screen
    /// controls for one leaves no way to play at all.
    private var wiredInputCount = 0
    var isConnected: Bool { current != nil && wiredInputCount > 0 }

    private var observers: [NSObjectProtocol] = []

    // Movement is the union of whatever the d-pad and left thumbstick are
    // each currently reporting, so releasing one source never cancels a
    // direction the other source is still holding.
    private var dpadDirections: Set<INDSButton> = []
    private var stickDirections: Set<INDSButton> = []

    private static let stickThreshold: Float = 0.5

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            self?.attach(controller)
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            self?.handleDisconnect(of: controller)
        })

        // A controller can already be connected before this manager exists
        // (e.g. paired over Bluetooth before the app launched) — connect
        // notifications only fire for NEW connections, so this initial scan
        // is required, not just a nicety.
        if let existing = GCController.controllers().first {
            attach(existing)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let current { releaseAllInputs(current) }
    }

    // MARK: - Connect / disconnect

    private func attach(_ controller: GCController) {
        guard current == nil else { return }
        current = controller
        INDSControllerMappingStore.activateProfile(for: controller)
        configureHandlers(controller)
        delegate?.gamepadManagerDidChangeConnection(self, connected: isConnected)
    }

    private func handleDisconnect(of controller: GCController) {
        guard controller === current else { return }
        releaseAllInputs(controller)
        current = nil
        delegate?.gamepadManagerDidChangeConnection(self, connected: false)

        // A second pad already connected while the first was active never
        // got a chance to attach (guarded above) — pick it up now instead of
        // leaving the app permanently controller-less until a fresh connect.
        if let next = GCController.controllers().first(where: { $0 !== controller }) {
            attach(next)
        }
    }

    private func releaseAllInputs(_ controller: GCController) {
        controller.controllerPausedHandler = nil
        INDSControllerElements.directionPad(on: controller)?.valueChangedHandler = nil
        INDSControllerElements.thumbstick(on: controller)?.valueChangedHandler = nil
        for (_, button) in INDSControllerElements.buttons(on: controller) {
            button.valueChangedHandler = nil
        }
        wiredInputCount = 0

        let held = dpadDirections.union(stickDirections)
        dpadDirections = []
        stickDirections = []
        for button in held { delegate?.gamepadManager(self, setButton: button, pressed: false) }
    }

    // MARK: - Handler wiring

    private func configureHandlers(_ controller: GCController) {
        controller.controllerPausedHandler = { [weak self] _ in
            guard let self else { return }
            self.delegate?.gamepadManager(self, perform: .pause)
        }

        wiredInputCount = 0

        if let dpad = INDSControllerElements.directionPad(on: controller) {
            wiredInputCount += 1
            dpad.valueChangedHandler = { [weak self] dpad, _, _ in
                self?.setDpadDirections(Self.directions(from: dpad))
            }
        }
        if let stick = INDSControllerElements.thumbstick(on: controller) {
            wiredInputCount += 1
            stick.valueChangedHandler = { [weak self] _, x, y in
                self?.setStickDirections(Self.directions(fromStickX: x, y: y))
            }
        }

        for (key, button) in INDSControllerElements.buttons(on: controller) {
            wiredInputCount += 1
            button.valueChangedHandler = { [weak self] _, _, pressed in
                self?.handlePhysical(key, pressed: pressed)
            }
        }

        if wiredInputCount == 0 {
            NSLog("[INDSGamepadManager] %@ exposes no input this app can read: %@",
                  controller.vendorName ?? "controller",
                  INDSControllerElements.detectedNames(on: controller).joined(separator: ", "))
        }
    }

    // MARK: - Physical input -> mapping target

    private func handlePhysical(_ key: String, pressed: Bool) {
        let target = INDSControllerMappingStore.target(forPhysical: key)

        if let button = target.indsButton {
            delegate?.gamepadManager(self, setButton: button, pressed: pressed)
            return
        }

        switch target {
        case .fastForward:
            delegate?.gamepadManager(self, setFastForwardActive: pressed)
        case .none:
            break
        default:
            // Discrete app actions (pause / quick save / quick load / cycle
            // layout / swap screens) fire once, on press only.
            guard pressed, let action = target.appAction else { return }
            delegate?.gamepadManager(self, perform: action)
        }
    }

    // MARK: - Movement (d-pad + thumbstick union, never remappable)

    private func setDpadDirections(_ next: Set<INDSButton>) {
        guard dpadDirections != next else { return }
        let before = dpadDirections.union(stickDirections)
        dpadDirections = next
        emitDirectionDiff(before: before, after: dpadDirections.union(stickDirections))
    }

    private func setStickDirections(_ next: Set<INDSButton>) {
        guard stickDirections != next else { return }
        let before = dpadDirections.union(stickDirections)
        stickDirections = next
        emitDirectionDiff(before: before, after: dpadDirections.union(stickDirections))
    }

    private func emitDirectionDiff(before: Set<INDSButton>, after: Set<INDSButton>) {
        guard before != after else { return }
        for button in before.subtracting(after) { delegate?.gamepadManager(self, setButton: button, pressed: false) }
        for button in after.subtracting(before) { delegate?.gamepadManager(self, setButton: button, pressed: true) }
    }

    private static func directions(from dpad: GCControllerDirectionPad) -> Set<INDSButton> {
        var result: Set<INDSButton> = []
        if dpad.up.isPressed { result.insert(.up) }
        if dpad.down.isPressed { result.insert(.down) }
        if dpad.left.isPressed { result.insert(.left) }
        if dpad.right.isPressed { result.insert(.right) }
        return result
    }

    private static func directions(fromStickX x: Float, y: Float) -> Set<INDSButton> {
        var result: Set<INDSButton> = []
        if y > stickThreshold { result.insert(.up) }
        if y < -stickThreshold { result.insert(.down) }
        if x < -stickThreshold { result.insert(.left) }
        if x > stickThreshold { result.insert(.right) }
        return result
    }
}
