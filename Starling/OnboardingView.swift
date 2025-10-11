//
//  OnboardingView.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    let onComplete: () -> Void
    
    private let totalPages = 5
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ZStack {
                if currentPage == 0 {
                    WelcomePage()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 1 {
                    MicrophonePage()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 2 {
                    AccessibilityPage()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 3 {
                    ModelDownloadPage()
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else if currentPage == 4 {
                    ReadyPage(onComplete: {
                        onComplete()
                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
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
                FeatureRow(icon: "🎤", text: "Speak naturally—VAD detects when you stop")
                FeatureRow(icon: "⚡️", text: "Transcription happens locally on your Mac")
                FeatureRow(icon: "📝", text: "Text pastes automatically at your cursor")
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
    @State private var microphoneAuthorized = false
    @State private var isChecking = false
    
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
            
            if microphoneAuthorized {
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
                Button("Request Microphone Access") {
                    requestMicrophonePermission()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking)
            }
            
            Text("You can change this later in System Settings → Privacy & Security → Microphone")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
        }
        .padding(40)
        .onAppear {
            checkMicrophoneStatus()
        }
    }
    
    private func checkMicrophoneStatus() {
        microphoneAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    private func requestMicrophonePermission() {
        isChecking = true
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneAuthorized = granted
                isChecking = false
            }
        }
    }
}

struct AccessibilityPage: View {
    @State private var accessibilityTrusted = false
    
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
                
                FeatureRow(icon: "⌘V", text: "Simulate paste keystrokes")
                FeatureRow(icon: "🎯", text: "Detect where your cursor is")
                FeatureRow(icon: "🔒", text: "Respect secure input fields")
            }
            .padding(.horizontal, 40)
            
            if accessibilityTrusted {
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
                Button("Open Accessibility Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                
                Text("After granting access, you may need to restart the app.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Button("Check Status") {
                checkAccessibilityStatus()
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .onAppear {
            checkAccessibilityStatus()
        }
    }
    
    private func checkAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }
    
    private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Also open System Settings
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cpu")
                        Text("Parakeet v3 Core ML model (~2.5 GB)")
                    }
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("Stored locally in ~/Library/Caches/")
                    }
                    HStack {
                        Image(systemName: "bolt.fill")
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
                    FeatureRow(icon: "🎙", text: "Press once to start, again to stop (or wait for silence)")
                    FeatureRow(icon: "⚙️", text: "Access Settings from the menu bar bird icon")
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
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon)
                .font(.title3)
                .frame(width: 30)
            Text(text)
                .font(.body)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}

