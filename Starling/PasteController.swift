//
//  PasteController.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AppKit
import Carbon.HIToolbox
import os

final class PasteController {
    private let logger = Logger(subsystem: "com.starling.app", category: "PasteController")
    private let pasteboard = NSPasteboard.general

    func paste(text: String, focusSnapshot: FocusSnapshot?, preserveClipboard: Bool) {
        let sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            logger.debug("Paste skipped because text was empty")
            return
        }

        let previousString: String? = preserveClipboard ? nil : pasteboard.string(forType: .string)

        let currentFocus = FocusSnapshot.capture()

        let focusChangeReason: FocusSnapshot.ChangeReason? = {
            if let snapshot = focusSnapshot {
                return snapshot.changeReason(comparedTo: currentFocus)
            } else {
                return .missingBaseline
            }
        }()

        let focusChanged = focusChangeReason != nil
        let secureInputActive = PasteController.isSecureInputActive()

        if let reason = focusChangeReason {
            logger.log("Preparing to paste. focusChanged=\(focusChanged, privacy: .public) reason=\(reason.logDescription, privacy: .public) secureInputActive=\(secureInputActive, privacy: .public)")
        } else {
            logger.log("Preparing to paste. focusChanged=false secureInputActive=\(secureInputActive, privacy: .public)")
        }

        writeToPasteboard(text: sanitized)

        if secureInputActive || focusChanged {
            if secureInputActive {
                logger.log("Copy fallback because secure input is active")
            }
            if let reason = focusChangeReason {
                logger.log("Copy fallback because \(reason.logDescription, privacy: .public)")
            }
            NotificationCenter.default.post(name: .pasteControllerDidCopy, object: sanitized)
            // In copy-only flow we always keep the transcript on the clipboard.
        } else {
            let pasteStartTime = CFAbsoluteTimeGetCurrent()
            synthesizePasteKeystroke()
            let pasteElapsed = (CFAbsoluteTimeGetCurrent() - pasteStartTime) * 1000
            logger.log("⏱️ Paste keystroke dispatched (\(Int(pasteElapsed), privacy: .public)ms)")
            NotificationCenter.default.post(name: .pasteControllerDidPaste, object: sanitized)
            if !preserveClipboard {
                restorePasteboard(previousString)
            }
        }
    }

    private func writeToPasteboard(text: String) {
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        logger.debug("Updated pasteboard with transcript (length=\(text.count, privacy: .public))")
    }

    private func synthesizePasteKeystroke() {
        logger.debug("Synthesizing ⌘V keystroke")
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create CGEventSource for paste keystroke")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = [.maskCommand]
        keyUp?.flags = [.maskCommand]

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func restorePasteboard(_ string: String?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.pasteboard.clearContents()
            if let string {
                self.pasteboard.setString(string, forType: .string)
            }
        }
    }

    static func isSecureInputActive() -> Bool {
        // macOS does not expose a public API to query secure input; rely on session dictionary
        let gid = CGSessionCopyCurrentDictionary() as? [String: Any]
        if let secure = gid?["CGSSessionSecureInputPID"] as? Int, secure != 0 {
            return true
        }
        return false
    }
}

extension Notification.Name {
    static let pasteControllerDidCopy = Notification.Name("com.starling.paste.didCopy")
    static let pasteControllerDidPaste = Notification.Name("com.starling.paste.didPaste")
}
