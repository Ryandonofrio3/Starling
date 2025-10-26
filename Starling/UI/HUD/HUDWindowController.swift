//
//  HUDWindowController.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class HUDWindowController: NSObject {
    private let panel: NonActivatingPanel
    private let hostingView: NSHostingView<HUDView>
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState
    private let preferences: PreferencesStore
    private let defaults = UserDefaults.standard
    private static let frameDefaultsKey = "com.starling.hud.panelFrame"

    init(appState: AppState, preferences: PreferencesStore = .shared) {
        self.appState = appState
        self.preferences = preferences
        let contentSize = NSSize(width: 320, height: 96)
        panel = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: [.nonactivatingPanel, .hudWindow], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true

        hostingView = NSHostingView(rootView: HUDView(appState: appState, preferences: preferences))
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        panel.contentView = hostingView

        super.init()

        panel.delegate = self
        applyInitialFrame()

        observeState()
    }

    private func observeState() {
        appState.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.update(for: phase)
            }
            .store(in: &cancellables)

        preferences.$minimalistMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.update(for: self.appState.phase)
            }
            .store(in: &cancellables)
    }

    private func update(for phase: AppState.Phase) {
        switch phase {
        case .idle:
            panel.orderOut(nil)
        default:
            if preferences.minimalistMode {
                panel.orderOut(nil)
            } else {
                if panel.isVisible == false {
                    applyInitialFrame()
                    panel.orderFrontRegardless()
                } else {
                    ensurePanelWithinVisibleSpace()
                }
            }
        }
    }

    private func applyInitialFrame() {
        if !restoreSavedFrame() {
            positionPanelAtDefaultLocation()
        }
    }

    private func ensurePanelWithinVisibleSpace() {
        guard let adjusted = adjustedFrameIfNeeded(for: panel.frame) else {
            positionPanelAtDefaultLocation()
            return
        }
        if adjusted != panel.frame {
            panel.setFrame(adjusted, display: false)
        }
    }

    private func positionPanelAtDefaultLocation() {
        guard let screen = NSScreen.main else { return }
        let margin: CGFloat = 24
        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width * 0.5,
            y: screenFrame.maxY - panelSize.height - margin
        )
        let frame = NSRect(origin: origin, size: panelSize)
        panel.setFrame(frame, display: false)
        defaults.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
    }

    @discardableResult
    private func restoreSavedFrame() -> Bool {
        guard let stored = defaults.string(forKey: Self.frameDefaultsKey) else {
            return false
        }

        let rect = NSRectFromString(stored)
        guard let adjusted = adjustedFrameIfNeeded(for: rect) else {
            return false
        }

        panel.setFrame(adjusted, display: false)
        return true
    }

    private func adjustedFrameIfNeeded(for frame: NSRect) -> NSRect? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        if screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            return frame
        }

        return nil
    }

    private func persistCurrentFrame() {
        guard panel.isVisible else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: Self.frameDefaultsKey)
    }
}

@MainActor
extension HUDWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        persistCurrentFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistCurrentFrame()
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown {
            performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

private struct HUDView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var preferences: PreferencesStore
    @State private var glow = false

    var body: some View {
        let presentation = HUDPresentation(
            phase: appState.phase,
            hotkeyDisplayString: preferences.hotkeyConfig.displayString,
            recordingMode: preferences.recordingMode
        )

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )

            HStack(spacing: 14) {
                if let iconName = presentation.iconName {
                    Image(iconName)
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 44, height: 44)
                        .shadow(color: presentation.animateGlow && glow ? .yellow.opacity(0.45) : .clear, radius: presentation.animateGlow && glow ? 18 : 0)
                        .scaleEffect(presentation.animateGlow && glow ? 1.08 : 1.0)
                        .animation(presentation.animateGlow ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: glow)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.title)
                        .font(.system(size: 16, weight: .semibold))

                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    if presentation.showWaveform {
                        WaveformVisualizer(level: appState.currentAudioLevel)
                            .padding(.top, 2)
                    }

                    if let warning = appState.audioWarning {
                        Text(warning)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 320, height: 96)
        .allowsHitTesting(false)
        .onAppear {
            glow = presentation.animateGlow
        }
        .onChange(of: appState.phase) { _, newPhase in
            let newPresentation = HUDPresentation(
                phase: newPhase,
                hotkeyDisplayString: preferences.hotkeyConfig.displayString,
                recordingMode: preferences.recordingMode
            )
            glow = newPresentation.animateGlow
        }
    }
}

private struct HUDPresentation {
    let title: String
    let detail: String?
    let iconName: String?
    let animateGlow: Bool
    let showWaveform: Bool

    init(phase: AppState.Phase, hotkeyDisplayString: String, recordingMode: PreferencesStore.RecordingMode) {
        switch phase {
        case .idle:
            title = ""
            detail = nil
            iconName = nil
            animateGlow = false
            showWaveform = false
        case .initializing(_):
            title = "Please wait"
            detail = "Downloading model…"
            iconName = "BirdTranscribing"
            animateGlow = false
            showWaveform = false
        case .listening:
            title = "Listening…"
            switch recordingMode {
            case .toggle:
                detail = "Press \(hotkeyDisplayString) to stop"
            case .holdToTalk:
                detail = "Release to stop"
            }
            iconName = "BirdListening"
            animateGlow = true
            showWaveform = true
        case .transcribing:
            title = "Transcribing…"
            detail = nil
            iconName = "BirdTranscribing"
            animateGlow = false
            showWaveform = false
        case .toast(let message):
            title = message
            detail = nil
            iconName = "BirdIdle"
            animateGlow = false
            showWaveform = false
        }
    }
}

private struct WaveformVisualizer: View {
    let level: Float
    private let barMultipliers: [CGFloat] = [0.45, 0.75, 1.0, 0.75, 0.45]
    @State private var displayedLevel: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(barMultipliers.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3, height: 20)
                    .modifier(WaveformHeightEffect(scale: barScale(for: index)))
            }
        }
        .frame(width: 24, height: 20, alignment: .bottom)
        .onAppear {
            displayedLevel = CGFloat(clamp(level))
        }
        .onChange(of: level) { _, newValue in
            withAnimation(.easeOut(duration: 0.15)) {
                displayedLevel = CGFloat(clamp(newValue))
            }
        }
    }

    private func barScale(for index: Int) -> CGFloat {
        max(displayedLevel * barMultipliers[index], 0.18)
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

private struct WaveformHeightEffect: GeometryEffect {
    var scale: CGFloat

    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let clamped = max(min(scale, 1), 0.18)
        let offset = (1 - clamped) * size.height / 2
        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: 1, y: clamped)
        transform = transform.translatedBy(x: 0, y: offset / max(clamped, .leastNonzeroMagnitude))
        return ProjectionTransform(transform)
    }
}
