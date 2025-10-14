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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Starling Preferences")
                    .font(.title2)
                    .bold()
                
                Divider()

                VStack(alignment: .leading, spacing: 16) {
                Text("Hotkey")
                    .font(.headline)
                
                HotkeyRecorderView(hotkeyConfig: $preferences.hotkeyConfig)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Activation Mode")
                        .font(.subheadline)

                    Picker("Activation Mode", selection: $preferences.recordingMode) {
                        ForEach(PreferencesStore.RecordingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Toggle starts and stops with a press. Hold to Talk records only while the hotkey is held.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
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

                Toggle("Force plain text only", isOn: $preferences.forcePlainTextOnly)
                    .toggleStyle(.switch)
                    .help("When enabled, Starling writes only plain text to the clipboard and clears other formats.")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-clear clipboard")
                        .font(.subheadline)

                    Picker("Auto-clear clipboard", selection: $preferences.clipboardAutoClear) {
                        ForEach(PreferencesStore.ClipboardAutoClear.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!preferences.keepTranscriptOnClipboard)
                    .help("Automatically clears the clipboard after the selected delay when Starling leaves the transcript there.")
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                Text("Voice Activity")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trailing Silence Duration")
                        .font(.subheadline)

                    HStack {
                        Slider(
                            value: Binding(
                                get: { preferences.trailingSilencePreference.sliderValue },
                                set: { newValue in
                                    preferences.trailingSilencePreference = PreferencesStore.TrailingSilencePreference.preference(fromSliderValue: newValue)
                                }
                            ),
                            in: PreferencesStore.TrailingSilencePreference.minimumSeconds...PreferencesStore.TrailingSilencePreference.manualSliderValue,
                            step: PreferencesStore.TrailingSilencePreference.sliderStep
                        )

                        Group {
                            switch preferences.trailingSilencePreference {
                            case let .automatic(seconds):
                                Text("\(seconds, format: .number.precision(.fractionLength(2))) s")
                                    .monospacedDigit()
                            case .manual:
                                Text("Manual (Press Esc to finish)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 180, alignment: .trailing)
                    }

                    Text("How long Starling waits after silence before auto-stopping. Manual requires finishing with your stop shortcut (Toggle hotkey or Esc).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .padding(.vertical, 4)

                Text("Text Cleanup")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Normalize spoken numbers", isOn: Binding(
                        get: { preferences.textCleanupOptions.normalizeNumbers },
                        set: { preferences.textCleanupOptions.normalizeNumbers = $0 }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Spoken punctuation → symbols", isOn: Binding(
                        get: { preferences.textCleanupOptions.spokenPunctuation },
                        set: { preferences.textCleanupOptions.spokenPunctuation = $0 }
                    ))
                    .toggleStyle(.switch)

                    Toggle("“New line” / “new paragraph”", isOn: Binding(
                        get: { preferences.textCleanupOptions.normalizeNewlines },
                        set: { preferences.textCleanupOptions.normalizeNewlines = $0 }
                    ))
                    .toggleStyle(.switch)

                    Toggle("Auto-capitalize first letter", isOn: Binding(
                        get: { preferences.textCleanupOptions.autoCapitalizeFirstWord },
                        set: { preferences.textCleanupOptions.autoCapitalizeFirstWord = $0 }
                    ))
                    .toggleStyle(.switch)

                    Text("Applies when options are turned on. Punctuation mapping also tidies spacing around symbols.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            }
            .padding(24)
        }
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
