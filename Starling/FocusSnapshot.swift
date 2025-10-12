//
//  FocusSnapshot.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AppKit
import ApplicationServices
import os

struct FocusSnapshot: Equatable {
    struct ElementSignature: Equatable {
        let role: String?
        let subrole: String?
        let identifier: String?
        let windowNumber: Int?
    }

    enum ChangeReason: Equatable {
        case missingBaseline
        case missingCurrent
        case applicationChanged(previous: pid_t, current: pid_t)
        case elementSignatureChanged
        case selectionSignatureChanged

        var logDescription: String {
            switch self {
            case .missingBaseline:
                return "baseline focus snapshot unavailable"
            case .missingCurrent:
                return "unable to capture current focus state"
            case let .applicationChanged(previous, current):
                return "frontmost application changed (\(previous) → \(current))"
            case .elementSignatureChanged:
                return "focused element signature differs"
            case .selectionSignatureChanged:
                return "text selection signature differs"
            }
        }
    }

    let appPID: pid_t
    let elementSignature: ElementSignature
    let selectionSignature: String?

    private static let windowNumberAttribute: CFString = "AXWindowNumber" as CFString
    private static let logger = Logger(subsystem: "com.starling.app", category: "FocusSnapshot")

    static func capture(using application: NSWorkspace = .shared) -> FocusSnapshot? {
        guard let app = application.frontmostApplication else {
            logger.debug("Focus capture failed: no frontmost application")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedElement: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard status == .success || status == .noValue, let elementRef = focusedElement else {
            logger.debug("Focus capture failed for pid=\(app.processIdentifier, privacy: .public); AXError=\(status.rawValue, privacy: .public)")
            return nil
        }
        let element = unsafeBitCast(elementRef, to: AXUIElement.self)
        let signature = captureElementSignature(for: element)
        let range = FocusSnapshot.captureTextRange(for: element)
        return FocusSnapshot(appPID: app.processIdentifier, elementSignature: signature, selectionSignature: range)
    }

    static func captureTextRange(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard status == .success, let rangeValue = value else {
            return nil
        }
        let axValue = unsafeBitCast(rangeValue, to: AXValue.self)
        var range = CFRange(location: 0, length: 0)
        if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) {
            return "\(range.location):\(range.length)"
        }
        return String(describing: axValue)
    }

    func hasFocusChanged(comparedTo other: FocusSnapshot?) -> Bool {
        changeReason(comparedTo: other) != nil
    }

    func changeReason(comparedTo other: FocusSnapshot?) -> ChangeReason? {
        guard let other else {
            return .missingCurrent
        }
        if appPID != other.appPID {
            return .applicationChanged(previous: appPID, current: other.appPID)
        }
        if elementSignature != other.elementSignature {
            return .elementSignatureChanged
        }
        if selectionSignature != other.selectionSignature {
            return .selectionSignatureChanged
        }
        return nil
    }

    private static func captureElementSignature(for element: AXUIElement) -> ElementSignature {
        let role = copyStringAttribute(element, kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element, kAXSubroleAttribute as CFString)
        let identifier = copyStringAttribute(element, kAXIdentifierAttribute as CFString)
        let windowNumber = captureWindowNumber(for: element)
        return ElementSignature(role: role, subrole: subrole, identifier: identifier, windowNumber: windowNumber)
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private static func captureWindowNumber(for element: AXUIElement) -> Int? {
        var windowRef: CFTypeRef?
        let windowStatus = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef)
        guard windowStatus == .success, let windowValue = windowRef else {
            return nil
        }
        let windowElement = unsafeBitCast(windowValue, to: AXUIElement.self)

        var numberValue: CFTypeRef?
        let numberStatus = AXUIElementCopyAttributeValue(windowElement, windowNumberAttribute, &numberValue)
        if numberStatus == .success {
            if let number = numberValue as? NSNumber {
                return number.intValue
            }
        }
        return nil
    }
}
