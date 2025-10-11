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
final class HUDWindowController {
    private let panel: NonActivatingPanel
    private let hostingView: NSHostingView<HUDView>
    private var cancellables = Set<AnyCancellable>()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
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

        hostingView = NSHostingView(rootView: HUDView(phase: .idle))
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        panel.contentView = hostingView

        observeState()
    }

    private func observeState() {
        appState.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.update(for: phase)
            }
            .store(in: &cancellables)
    }

    private func update(for phase: AppState.Phase) {
        hostingView.rootView = HUDView(phase: phase)

        switch phase {
        case .idle:
            panel.orderOut(nil)
        default:
            if panel.isVisible == false {
                positionPanel()
                panel.orderFrontRegardless()
            }
            // Keep the panel in sync with the main screen if users move displays.
            positionPanel()
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else {
            return
        }
        let margin: CGFloat = 24
        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width * 0.5,
            y: screenFrame.maxY - panelSize.height - margin
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct HUDView: View {
    let phase: AppState.Phase
    @State private var glow = false

    var body: some View {
        let presentation = HUDPresentation(phase: phase)

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )

            HStack(spacing: 16) {
                if let iconName = presentation.iconName {
                    Image(iconName)
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 48, height: 48)
                        .shadow(color: presentation.animateGlow && glow ? .yellow.opacity(0.45) : .clear, radius: presentation.animateGlow && glow ? 18 : 0)
                        .scaleEffect(presentation.animateGlow && glow ? 1.08 : 1.0)
                        .animation(presentation.animateGlow ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: glow)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.system(size: 17, weight: .semibold))
                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(width: 320, height: 96)
        .allowsHitTesting(false)
        .onAppear {
            glow = presentation.animateGlow
        }
        .onChange(of: phase) { _, newPhase in
            let newPresentation = HUDPresentation(phase: newPhase)
            if newPresentation.animateGlow {
                glow = true
            } else {
                glow = false
            }
        }
    }
}

private struct HUDPresentation {
    let title: String
    let detail: String?
    let iconName: String?
    let animateGlow: Bool

    init(phase: AppState.Phase) {
        switch phase {
        case .idle:
            title = ""
            detail = nil
            iconName = nil
            animateGlow = false
        case .initializing(let progress):
            title = "Preparing model…"
            if let progress {
                detail = "\(Int(progress * 100))%"
            } else {
                detail = "Downloading components"
            }
            iconName = "BirdTranscribing"
            animateGlow = false
        case .listening:
            title = "Listening…"
            detail = "Press ⌃⌥⌘J to stop"
            iconName = "BirdListening"
            animateGlow = true
        case .transcribing:
            title = "Transcribing…"
            detail = nil
            iconName = "BirdTranscribing"
            animateGlow = false
        case .toast(let message):
            title = message
            detail = nil
            iconName = "BirdIdle"
            animateGlow = false
        }
    }
}
