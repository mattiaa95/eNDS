//
//  NDSPauseMenuHostingController.swift
//  eNDS
//
//  Ported and adapted from iGBA's PauseMenuHostingController.swift
//  (GBA-Emu repo): a UIKit sheet that hosts the SwiftUI pause menu, with a
//  swipe-down-resumes gesture layered over the sheet's own interactive
//  dismissal so "just swipe it away" behaves the same as tapping Resume.
//

import SwiftUI

final class NDSPauseMenuHostingController: UIViewController, UIGestureRecognizerDelegate {

    private var hostingController: UIViewController?
    private var didDismissViaAction = false
    private var onDismissWithoutAction: (() -> Void)?
    private weak var swipeDownGesture: UISwipeGestureRecognizer?

    init(romTitle: String,
         romBaseName: String,
         currentSpeed: Double,
         saveSlots: [NDSSaveStateSlotInfo],
         loadSlots: [NDSSaveStateSlotInfo],
         currentVolume: Double,
         currentLayoutMode: DSScreenLayoutMode,
         currentSwapEnabled: Bool,
         currentStretchEnabled: Bool,
         currentDisplayFilter: NDSDisplayFilter,
         clipRecorder: NDSClipRecorder,
         onAction: @escaping (NDSPauseMenuAction) -> Void,
         onResume: @escaping () -> Void,
         onSpeedChanged: @escaping (Double) -> Void,
         onVolumeChanged: @escaping (Double) -> Void,
         onCycleLayout: @escaping () -> DSScreenLayoutMode,
         onToggleSwap: @escaping (Bool) -> Void,
         onToggleStretch: @escaping (Bool) -> Void,
         onCheatsChanged: @escaping () -> Void,
         onDisplayFilterChanged: @escaping (NDSDisplayFilter) -> Void,
         onToggleClipRecording: @escaping () -> Void) {
        super.init(nibName: nil, bundle: nil)

        let menuView = NDSPauseMenuView(
            romTitle: romTitle,
            romBaseName: romBaseName,
            currentSpeed: currentSpeed,
            saveSlots: saveSlots,
            loadSlots: loadSlots,
            initialVolume: currentVolume,
            initialLayoutMode: currentLayoutMode,
            initialSwapEnabled: currentSwapEnabled,
            initialStretchEnabled: currentStretchEnabled,
            initialDisplayFilter: currentDisplayFilter,
            clipRecorder: clipRecorder,
            onAction: { [weak self] action in
                self?.didDismissViaAction = true
                onAction(action)
            },
            onResume: { [weak self] in
                self?.didDismissViaAction = true
                onResume()
            },
            onSpeedChanged: onSpeedChanged,
            onVolumeChanged: onVolumeChanged,
            onCycleLayout: onCycleLayout,
            onToggleSwap: onToggleSwap,
            onToggleStretch: onToggleStretch,
            onCheatsChanged: onCheatsChanged,
            onDisplayFilterChanged: onDisplayFilterChanged,
            onToggleClipRecording: onToggleClipRecording
        )
        .tint(INDSAppearanceStore.shared.accentColor)

        let hosting = UIHostingController(rootView: menuView)
        hosting.view.backgroundColor = .clear
        self.hostingController = hosting
        self.onDismissWithoutAction = onResume

        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
        isModalInPresentation = true

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown))
        swipeDown.direction = .down
        swipeDown.delegate = self
        view.addGestureRecognizer(swipeDown)
        swipeDownGesture = swipeDown

        guard let hosting = hostingController else { return }
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    @objc private func handleSwipeDown() {
        // Always resume. `didDismissViaAction` latches on ANY onAction, including
        // the ones that leave the sheet open (Save State, cheats, filters) — so
        // skipping the resume here left the game frozen forever after a save.
        // The flag can't protect against a double resume in this path anyway:
        // viewWillDisappear removes this recognizer as soon as an action-driven
        // dismissal starts, and resumeEmulation is idempotent regardless.
        onDismissWithoutAction?()
        dismiss(animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeDownGesture else { return true }
        let startPoint = gestureRecognizer.location(in: view)
        let edgeInset: CGFloat = 24
        return startPoint.x > edgeInset && startPoint.x < view.bounds.width - edgeInset
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let swipeDownGesture {
            view.removeGestureRecognizer(swipeDownGesture)
        }
        if let hosting = hostingController {
            hosting.willMove(toParent: nil)
            hosting.view.removeFromSuperview()
            hosting.removeFromParent()
        }
        hostingController = nil
        didDismissViaAction = false
    }
}
