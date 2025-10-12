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
    private var autoClearWorkItem: DispatchWorkItem?

    enum Outcome {
        case pasted
        case copiedFallback
        case skipped
    }
    func paste(text: String, focusSnapshot: FocusSnapshot?, preserveClipboard: Bool, forcePlainTextOnly: Bool, autoClearDelay: TimeInterval?) -> Outcome {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else {
            logger.debug("Paste skipped because text was empty")
            return .skipped
        }
        let sanitized = normalizeLineEndings(for: text.trimmingCharacters(in: .whitespaces))

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

        let shouldScheduleAutoClear = preserveClipboard || secureInputActive || focusChanged
        var finalChangeCount = pasteboard.changeCount
        var outcome: Outcome = .pasted

        if secureInputActive || focusChanged {
            // Copy fallback path: ensure clipboard contains sanitized text
            writeToPasteboard(text: sanitized, forcePlainTextOnly: forcePlainTextOnly)
            finalChangeCount = pasteboard.changeCount
            if secureInputActive {
                logger.log("Copy fallback because secure input is active")
            }
            if let reason = focusChangeReason {
                logger.log("Copy fallback because \(reason.logDescription, privacy: .public)")
            }
            NotificationCenter.default.post(name: .pasteControllerDidCopy, object: sanitized)
            outcome = .copiedFallback
        } else {
            if sanitized.contains("\n") {
                finalChangeCount = performSegmentedPaste(text: sanitized, forcePlainTextOnly: forcePlainTextOnly)
                NotificationCenter.default.post(name: .pasteControllerDidPaste, object: sanitized)
                if !preserveClipboard {
                    restorePasteboard(previousString)
                }
            } else {
                // Simple single paste
                writeToPasteboard(text: sanitized, forcePlainTextOnly: forcePlainTextOnly)
                finalChangeCount = pasteboard.changeCount
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

        let expectedClipboardText = pasteboard.string(forType: .string)
        scheduleAutoClearIfNeeded(expectedText: expectedClipboardText, changeCount: finalChangeCount, delay: autoClearDelay, shouldSchedule: shouldScheduleAutoClear)

        return outcome
    }

    private func writeToPasteboard(text: String, forcePlainTextOnly: Bool) {
        pasteboard.clearContents()
        if !forcePlainTextOnly {
            let attributed = NSAttributedString(string: text)
            if let data = try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                pasteboard.setData(data, forType: .rtf)
            }
        }
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

    private func synthesizeReturnKeystroke() {
        logger.debug("Synthesizing ⏎ Return keystroke")
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create CGEventSource for return keystroke")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)

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

    private func scheduleAutoClearIfNeeded(expectedText: String?, changeCount: Int, delay: TimeInterval?, shouldSchedule: Bool) {
        autoClearWorkItem?.cancel()
        guard shouldSchedule, let delay, delay > 0, let expected = expectedText else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.clearClipboardIfUnchanged(expectedText: expected, changeCount: changeCount)
        }
        autoClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func clearClipboardIfUnchanged(expectedText: String, changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        guard pasteboard.string(forType: .string) == expectedText else { return }

        pasteboard.clearContents()
        logger.log("Cleared clipboard after privacy timeout")
    }

    private func normalizeLineEndings(for text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    private func performSegmentedPaste(text: String, forcePlainTextOnly: Bool) -> Int {
        // Split text into segments separated by one or more newlines
        // For each segment, paste the text then synthesize Return for each newline encountered
        var buffer = ""
        var newlineCount = 0
        var lastChangeCount = pasteboard.changeCount

        func flushBuffer() {
            if !buffer.isEmpty {
                writeToPasteboard(text: buffer, forcePlainTextOnly: forcePlainTextOnly)
                lastChangeCount = pasteboard.changeCount
                let pasteStart = CFAbsoluteTimeGetCurrent()
                synthesizePasteKeystroke()
                let elapsed = (CFAbsoluteTimeGetCurrent() - pasteStart) * 1000
                logger.log("⏱️ Segmented paste dispatched (\(Int(elapsed), privacy: .public)ms, length=\(buffer.count, privacy: .public))")
                buffer.removeAll(keepingCapacity: true)
            }
            if newlineCount > 0 {
                for _ in 0..<newlineCount { synthesizeReturnKeystroke() }
                logger.debug("Inserted \(newlineCount, privacy: .public) return keystroke(s)")
                newlineCount = 0
            }
        }

        for character in text {
            if character == "\n" {
                newlineCount += 1
            } else {
                if newlineCount > 0 { flushBuffer() }
                buffer.append(character)
            }
        }

        // Flush any remaining buffer and returns at the end
        flushBuffer()
        return lastChangeCount
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
