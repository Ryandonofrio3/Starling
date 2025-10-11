//
//  HotkeyManager.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import Carbon
import Foundation

struct HotkeyConfig: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    
    static let `default` = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_J),
        modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
    )
    
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if let key = Self.keyCodeToString(keyCode) {
            parts.append(key)
        }
        return parts.joined()
    }
    
    private static func keyCodeToString(_ code: UInt32) -> String? {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return nil
        }
    }
}

enum HotkeyError: Error {
    case registrationFailed(OSStatus)
    case installationFailed(OSStatus)
}

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    func register(config: HotkeyConfig, handler: @escaping () -> Void) throws {
        try registerHotkey(keyCode: config.keyCode, modifiers: config.modifiers, handler: handler)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        handler = nil
    }

    deinit {
        unregister()
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        unregister()

        self.handler = handler

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr, let hotKeyRef else {
            throw HotkeyError.registrationFailed(status)
        }
        self.hotKeyRef = hotKeyRef

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), Self.eventCallback, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &eventHandlerRef)
        guard installStatus == noErr else {
            unregister()
            throw HotkeyError.installationFailed(installStatus)
        }
    }

    private static let identifier: UInt32 = 1
    private static let signature: OSType = "PPHK".fourCharCode

    private static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return noErr
        }

        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

        if status == noErr, hotKeyID.signature == signature, hotKeyID.id == identifier {
            manager.handler?()
        }

        return noErr
    }
}

private extension String {
    var fourCharCode: OSType {
        var result: UInt32 = 0
        for scalar in utf16.prefix(4) {
            result = (result << 8) + UInt32(scalar)
        }
        return OSType(result)
    }
}
