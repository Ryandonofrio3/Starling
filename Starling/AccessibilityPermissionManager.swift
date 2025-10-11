//
//  AccessibilityPermissionManager.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import ApplicationServices
import Foundation

final class AccessibilityPermissionManager {
    func isTrusted(promptIfNeeded: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
