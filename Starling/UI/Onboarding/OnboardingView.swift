//
//  OnboardingView.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var microphonePermission: MicrophonePermissionMonitor
    @ObservedObject private var accessibilityPermission: AccessibilityPermissionMonitor
    @State private var currentPage = 0
    let onComplete: () -> Void

    private let totalPages = 5

    init(
        microphonePermission: MicrophonePermissionMonitor = .shared,
        accessibilityPermission: AccessibilityPermissionMonitor = .shared,
        onComplete: @escaping () -> Void
    ) {
        self._microphonePermission = ObservedObject(wrappedValue: microphonePermission)
        self._accessibilityPermission = ObservedObject(wrappedValue: accessibilityPermission)
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ZStack {
                if currentPage == 0 {
                    WelcomePage()
                        .transition(Self.pageTransition)
                } else if currentPage == 1 {
                    MicrophonePage(permission: microphonePermission)
                        .transition(Self.pageTransition)
                } else if currentPage == 2 {
                    AccessibilityPage(permission: accessibilityPermission)
                        .transition(Self.pageTransition)
                } else if currentPage == 3 {
                    ModelDownloadPage()
                        .transition(Self.pageTransition)
                } else if currentPage == 4 {
                    ReadyPage(onComplete: {
                        onComplete()
                    })
                    .transition(Self.pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut, value: currentPage)
                }
            }
            .padding(.vertical, 16)
            
            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
                
                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .frame(width: 600, height: 500)
    }
}

private extension OnboardingView {
    static var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: Edge.trailing),
            removal: .move(edge: Edge.leading)
        )
    }
}

struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("BirdIdle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
            
            Text("Welcome to Starling")
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "⌃⌥⌘J", text: "Press your hotkey to start recording")
                FeatureRow(icon: "mic", text: "Speak naturally—stops when you pause", isSystemIcon: true)
                FeatureRow(icon: "cpu", text: "Transcription happens locally on your Mac", isSystemIcon: true)
                FeatureRow(icon: "text.cursor", text: "Text pastes automatically at your cursor", isSystemIcon: true)
            }
            .padding(.horizontal, 40)
            
            Text("Let's get you set up in a few quick steps.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}

struct MicrophonePage: View {
    @ObservedObject var permission: MicrophonePermissionMonitor
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Microphone Access")
                .font(.title)
                .bold()
            
            Text("Starling needs microphone access to transcribe your voice.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if permission.state.isAuthorized {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Microphone access granted")
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    if permission.state.needsPrompt {
                        Button("Request Microphone Access") {
                            requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRequesting)
                    } else {
                        Button("Open Microphone Settings") {
                            permission.openSystemSettings()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if permission.state.isBlocked {
                        Text("Grant access in System Settings → Privacy & Security → Microphone, then come back here.")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }

            Text("You can change this later in System Settings → Privacy & Security → Microphone")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
        }
        .padding(40)
        .onAppear {
            permission.refresh()
        }
    }

    private func requestPermission() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            let granted = await permission.requestAccess()
            await MainActor.run {
                isRequesting = false
                if !granted && permission.state.isBlocked {
                    permission.openSystemSettings()
                }
            }
        }
    }
}

struct AccessibilityPage: View {
    @ObservedObject var permission: AccessibilityPermissionMonitor

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 64))
                .foregroundColor(.purple)
            
            Text("Accessibility Access")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Starling needs Accessibility permissions to:")
                    .font(.body)
                
                FeatureRow(icon: "command", text: "Simulate paste keystrokes", isSystemIcon: true)
                FeatureRow(icon: "cursorarrow.rays", text: "Detect where your cursor is", isSystemIcon: true)
                FeatureRow(icon: "lock.fill", text: "Respect secure input fields", isSystemIcon: true)
            }
            .padding(.horizontal, 40)
            
            if permission.isTrusted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Accessibility access granted")
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                VStack(spacing: 12) {
                    Button("Open Accessibility Settings") {
                        permission.requestAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Text("After granting access, Starling will auto-detect it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .padding(40)
        .onAppear {
            permission.refresh()
        }
    }
}

struct ModelDownloadPage: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Model Download")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("On first use, Starling will download:")
                    .font(.body)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Parakeet v3 Core ML model (~2.5 GB)")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Stored locally in ~/Library/Caches/")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Uses Neural Engine for fast transcription")
                    }
                }
                .padding(.leading, 20)
            }
            .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("The download happens automatically when you first record.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("You'll see a progress indicator in the menu bar.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            
            HStack(spacing: 16) {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)
                Text("Requires internet connection on first launch only")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
    }
}

struct ReadyPage: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image("BirdListening")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
            
            Text("You're All Set!")
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Reference:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "⌃⌥⌘J", text: "Default hotkey (customizable in Settings)")
                    FeatureRow(icon: "waveform", text: "Press once to start, again to stop (or wait for silence)", isSystemIcon: true)
                    FeatureRow(icon: "gearshape", text: "Access Settings from the menu bar bird icon", isSystemIcon: true)
                }
            }
            .padding(.horizontal, 40)
            
            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    var isSystemIcon: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSystemIcon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            } else {
                Text(icon)
                    .font(.title3)
                    .frame(width: 30)
            }
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
