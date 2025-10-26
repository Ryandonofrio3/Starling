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
                    HStack(spacing: 6) {
                        Text("Hotkey")
                            .font(.headline)
                        InfoTooltip(message: "Set the shortcut used to start and stop Starling.")
                    }

                    HotkeyRecorderView(hotkeyConfig: $preferences.hotkeyConfig)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Activation Mode")
                                .font(.subheadline)
                            InfoTooltip(message: "Choose between a toggle press or hold-to-talk recording.")
                        }

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
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Text("Clipboard")
                            .font(.headline)
                        InfoTooltip(message: "Control how Starling manages clipboard contents after transcribing.")
                    }

                    Toggle("Keep transcript on clipboard after auto-paste", isOn: $preferences.keepTranscriptOnClipboard)
                        .toggleStyle(.switch)
                        .help("When disabled, the previous clipboard contents are restored after auto-paste. Copy fallback always keeps the transcript available.")

                    Text("Normally, Starling restores your previous clipboard after pasting. Enable this to keep the transcript available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Force plain text only", isOn: $preferences.forcePlainTextOnly)
                        .toggleStyle(.switch)
                        .help("When enabled, Starling writes only plain text to the clipboard and clears other formats.")

                    Text("Removes formatting when pasting into rich text apps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Auto-clear clipboard")
                                .font(.subheadline)
                            InfoTooltip(message: "Automatically wipe the transcript from the clipboard after your selected delay.")
                        }

                        Picker("Auto-clear clipboard", selection: $preferences.clipboardAutoClear) {
                            ForEach(PreferencesStore.ClipboardAutoClear.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!preferences.keepTranscriptOnClipboard)
                        .help("Automatically clears the clipboard after the selected delay when Starling leaves the transcript there.")

                        Text("For privacy, automatically removes transcript from clipboard after delay.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Text("Voice Activity")
                            .font(.headline)
                        InfoTooltip(message: "Control whether Starling auto-stops on silence or waits for you to manually stop.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Stop Mode")
                                .font(.subheadline)
                            InfoTooltip(message: "Choose between automatic silence detection or manual stopping.")
                        }

                        Picker("Stop Mode", selection: Binding(
                            get: { preferences.trailingSilenceConfig.mode },
                            set: { preferences.trailingSilenceConfig.mode = $0 }
                        )) {
                            ForEach(PreferencesStore.TrailingSilenceConfig.Mode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if preferences.trailingSilenceConfig.mode == .automatic {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Trailing Silence Duration")
                                    .font(.subheadline)
                                    .padding(.top, 4)

                                HStack {
                                    Slider(value: Binding(
                                        get: { preferences.trailingSilenceConfig.duration },
                                        set: { preferences.trailingSilenceConfig.duration = $0 }
                                    ), in: 0.3...3.0, step: 0.05)
                                    Text("\(preferences.trailingSilenceConfig.duration, format: .number.precision(.fractionLength(2))) s")
                                        .monospacedDigit()
                                        .frame(width: 60, alignment: .trailing)
                                }

                                Text("How long Starling waits after silence before auto-stopping. Longer values are kinder to dramatic pauses.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Manual mode disables auto-stop. Press your hotkey again or use ESC to stop recording.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Text("Display")
                            .font(.headline)
                        InfoTooltip(message: "Fine-tune the floating HUD and menu bar presentation.")
                    }

                    Toggle("Minimalist mode", isOn: $preferences.minimalistMode)
                        .toggleStyle(.switch)
                        .help("Hides the HUD window. Only the menu bar icon will indicate recording state.")

                    Text("Hides the floating HUD window. The menu bar icon still shows recording state.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 6) {
                        Text("Text Cleanup")
                            .font(.headline)
                        InfoTooltip(message: "Tell Starling how to tidy transcripts before they are pasted.")
                    }

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

private struct InfoTooltip: View {
    let message: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.secondary)
            .help(message)
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
