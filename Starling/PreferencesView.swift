//
//  PreferencesView.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import SwiftUI
import Carbon

struct PreferencesView: View {
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Starling Preferences")
                .font(.title2)
                .bold()
            
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Hotkey")
                    .font(.headline)
                
                HotkeyRecorderView(hotkeyConfig: $preferences.hotkeyConfig)
                
                Text("Press the button and type your desired hotkey combination. Requires ⌘, ⌃, or ⌥.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                    .padding(.vertical, 4)
                
                Text("Clipboard")
                    .font(.headline)
                
                Toggle("Keep transcript on clipboard after auto-paste", isOn: $preferences.keepTranscriptOnClipboard)
                    .toggleStyle(.switch)
                    .help("When disabled, the previous clipboard contents are restored after auto-paste. Copy fallback always keeps the transcript available.")
                
                Divider()
                    .padding(.vertical, 4)
                
                Text("Voice Activity")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trailing Silence Duration")
                        .font(.subheadline)
                    
                    HStack {
                        Slider(value: $preferences.trailingSilenceDuration, in: 0.3...1.5, step: 0.05)
                        Text("\(preferences.trailingSilenceDuration, format: .number.precision(.fractionLength(2))) s")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                    
                    Text("How long Starling waits after silence before auto-stopping. Longer values are kinder to dramatic pauses.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 480)
    }
}

struct HotkeyRecorderView: View {
    @Binding var hotkeyConfig: HotkeyConfig
    @State private var isRecording = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text("Toggle Recording:")
                .font(.subheadline)
            
            Button(action: {
                isRecording.toggle()
                if isRecording {
                    isFocused = true
                }
            }) {
                Text(isRecording ? "Recording..." : hotkeyConfig.displayString)
                    .frame(minWidth: 100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isRecording ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .overlay(
                HotkeyRecorderInvisibleView(
                    isRecording: $isRecording,
                    onHotkeyRecorded: { config in
                        hotkeyConfig = config
                        isRecording = false
                        isFocused = false
                    }
                )
                .focused($isFocused)
                .frame(width: 0, height: 0)
            )
            
            if hotkeyConfig != .default {
                Button("Reset") {
                    hotkeyConfig = .default
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct HotkeyRecorderInvisibleView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onHotkeyRecorded: (HotkeyConfig) -> Void
    
    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onHotkeyRecorded = onHotkeyRecorded
        return view
    }
    
    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
    }
}

final class HotkeyRecorderNSView: NSView {
    var isRecording = false
    var onHotkeyRecorded: ((HotkeyConfig) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        
        // Require at least one modifier key (Cmd, Ctrl, or Option)
        let hasRequiredModifier = modifierFlags.contains(.command) || 
                                  modifierFlags.contains(.control) || 
                                  modifierFlags.contains(.option)
        
        guard hasRequiredModifier else { return }
        
        var modifiers: UInt32 = 0
        if modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        
        let config = HotkeyConfig(keyCode: UInt32(keyCode), modifiers: modifiers)
        onHotkeyRecorded?(config)
    }
}

#Preview {
    PreferencesView()
        .environmentObject(PreferencesStore.shared)
}
