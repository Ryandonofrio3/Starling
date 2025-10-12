//
//  TextNormalizer.swift
//  Starling
//
//  Created by ChatGPT on 11/24/23.
//

import Foundation

struct TextNormalizer {
    private static let punctuationCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters
        set.formUnion(.symbols)
        return set
    }()

    private static let newlinePatterns: [(regex: NSRegularExpression, replacement: String)] = {
        let patterns: [(String, String)] = [
            // New paragraph variants: "new paragraph", "new-paragraph", "newparagraph" (+ optional trailing punctuation)
            (#"(?i)\bnew[-\s]*paragraphs?\b[\.,!\?;:]*"#, "\n\n"),
            (#"(?i)\bnewparagraphs?\b[\.,!\?;:]*"#, "\n\n"),
            // New line variants: "new line", "new-line", "newline" (+ optional trailing punctuation)
            (#"(?i)\bnew[-\s]*line(s)?\b[\.,!\?;:]*"#, "\n"),
            (#"(?i)\bnewline(s)?\b[\.,!\?;:]*"#, "\n")
        ]
        return patterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (regex, replacement)
        }
    }()

    private static let punctuationPatterns: [(regex: NSRegularExpression, replacement: String)] = {
        let mappings: [(String, String)] = [
            (#"(?i)\bcomma\b"#, ","),
            (#"(?i)\bperiod\b"#, "."),
            (#"(?i)\bfull\s+stop\b"#, "."),
            (#"(?i)\bquestion\s+mark\b"#, "?"),
            (#"(?i)\bexclamation\s+(?:point|mark)\b"#, "!"),
            (#"(?i)\bcolon\b"#, ":"),
            (#"(?i)\bsemicolon\b"#, ";"),
            (#"(?i)\bdash\b"#, "—"),
            (#"(?i)\bellipsis\b"#, "…"),
            (#"(?i)\bopen\s+quote\b"#, "\""),
            (#"(?i)\bclose\s+quote\b"#, "\""),
            (#"(?i)\bopen\s+paren(?:thesis)?\b"#, "("),
            (#"(?i)\bclose\s+paren(?:thesis)?\b"#, ")")
        ]
        return mappings.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (regex, replacement)
        }
    }()

    private static let multiSpaceRegex = try! NSRegularExpression(pattern: "[\\t ]{2,}")
    private static let spaceBeforePunctuationRegex = try! NSRegularExpression(pattern: #"\s+([,.:;!?])"#)
    private static let spaceAfterOpeningRegex = try! NSRegularExpression(pattern: #"([(\[{])\s+"#)
    private static let punctuationSpacingRegex = try! NSRegularExpression(pattern: #"([,.:;!?])(\S)"#)
    private static let spacesAroundNewlineRegex = try! NSRegularExpression(pattern: #" *\n *"#)
    private static let excessiveNewlinesRegex = try! NSRegularExpression(pattern: #"\n{3,}"#)

    private static let unitNumbers: [String: Int] = [
        "zero": 0,
        "one": 1,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9
    ]

    private static let teenNumbers: [String: Int] = [
        "ten": 10,
        "eleven": 11,
        "twelve": 12,
        "thirteen": 13,
        "fourteen": 14,
        "fifteen": 15,
        "sixteen": 16,
        "seventeen": 17,
        "eighteen": 18,
        "nineteen": 19
    ]

    private static let tensNumbers: [String: Int] = [
        "twenty": 20,
        "thirty": 30,
        "forty": 40,
        "fifty": 50,
        "sixty": 60,
        "seventy": 70,
        "eighty": 80,
        "ninety": 90
    ]

    private enum NumberTokenType {
        case unit
        case teen
        case ten
        case hundred
        case thousand
    }

    func normalize(_ text: String, options: PreferencesStore.TextCleanupOptions) -> String {
        var working = text

        if options.normalizeNewlines {
            working = replaceNewlinePhrases(in: working)
        }

        if options.spokenPunctuation {
            working = replaceSpokenPunctuation(in: working)
        }

        if options.normalizeNumbers {
            working = normalizeSpokenNumbers(in: working)
        }

        working = cleanupWhitespace(working)

        if options.autoCapitalizeFirstWord {
            working = capitalizeFirstLetter(of: working)
        }

        working = cleanupWhitespace(working)

        return working
    }

    // MARK: - Replacement helpers

    private func replaceNewlinePhrases(in text: String) -> String {
        var result = text
        for mapping in Self.newlinePatterns {
            result = replace(mapping.regex, in: result, with: mapping.replacement)
        }
        return result
    }

    private func replaceSpokenPunctuation(in text: String) -> String {
        var result = text
        for mapping in Self.punctuationPatterns {
            result = replace(mapping.regex, in: result, with: mapping.replacement)
        }
        return result
    }

    private func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    // MARK: - Number normalization

    private func normalizeSpokenNumbers(in text: String) -> String {
        if text.isEmpty { return text }

        // Preserve newline tokens by surrounding them with spaces before splitting
        let prepared = text.replacingOccurrences(of: "\n", with: " \n ")
        let rawTokens = prepared.split(whereSeparator: { $0.isWhitespace }).map { String($0) }

        var outputTokens: [String] = []
        var index = 0

        while index < rawTokens.count {
            let token = rawTokens[index]

            if token == "\n" {
                outputTokens.append("\n")
                index += 1
                continue
            }

            if let parsed = parseNumberSequence(in: rawTokens, startingAt: index) {
                outputTokens.append(parsed.replacement)
                index += parsed.consumed
            } else {
                outputTokens.append(token)
                index += 1
            }
        }

        return rebuildString(from: outputTokens)
    }

    private func parseNumberSequence(in tokens: [String], startingAt start: Int) -> (replacement: String, consumed: Int)? {
        var total = 0
        var current = 0
        var consumed = 0
        var index = start
        var leadingPrefix = ""
        var trailingSuffix = ""
        var foundValue = false
        var lastType: NumberTokenType?

        while index < tokens.count {
            let raw = tokens[index]
            if raw == "\n" { break }

            let parts = stripToken(raw)
            if consumed == 0 {
                leadingPrefix = parts.leading
            } else if !parts.leading.isEmpty {
                break
            }

            let coreLower = parts.core.lowercased()
            if coreLower.isEmpty || containsDigits(coreLower) {
                break
            }

            if coreLower == "and" {
                if lastType == nil { break }
                consumed += 1
                index += 1
                continue
            } else if let value = Self.unitNumbers[coreLower] {
                if let last = lastType, last == .unit || last == .teen {
                    break
                }
                current += value
                lastType = .unit
                foundValue = true
            } else if let value = Self.teenNumbers[coreLower] {
                if let last = lastType, [.unit, .teen, .ten].contains(last) {
                    break
                }
                current += value
                lastType = .teen
                foundValue = true
            } else if let value = Self.tensNumbers[coreLower] {
                if let last = lastType, [.ten, .teen].contains(last) {
                    break
                }
                current += value
                lastType = .ten
                foundValue = true
            } else if coreLower == "hundred" {
                if let last = lastType, last == .hundred {
                    break
                }
                if current == 0 { current = 1 }
                current *= 100
                lastType = .hundred
                foundValue = true
            } else if coreLower == "thousand" {
                if let last = lastType, last == .thousand {
                    break
                }
                if current == 0 { current = 1 }
                current *= 1000
                total += current
                current = 0
                lastType = .thousand
                foundValue = true
            } else {
                break
            }

            trailingSuffix = parts.trailing
            consumed += 1
            index += 1
        }

        if consumed == 0 || !foundValue {
            return nil
        }

        total += current
        let replacement = leadingPrefix + String(total) + trailingSuffix
        return (replacement, consumed)
    }

    private func stripToken(_ token: String) -> (leading: String, core: String, trailing: String) {
        var leading = ""
        var trailing = ""
        var startIndex = token.startIndex
        var endIndex = token.endIndex

        while startIndex < endIndex,
              let scalar = token[startIndex].unicodeScalars.first,
              Self.punctuationCharacterSet.contains(scalar) {
            leading.append(token[startIndex])
            startIndex = token.index(after: startIndex)
        }

        while startIndex < endIndex {
            let previous = token.index(before: endIndex)
            if let scalar = token[previous].unicodeScalars.first,
               Self.punctuationCharacterSet.contains(scalar) {
                trailing.insert(token[previous], at: trailing.startIndex)
                endIndex = previous
            } else {
                break
            }
        }

        let core = String(token[startIndex..<endIndex])
        return (leading, core, trailing)
    }

    private func containsDigits(_ string: String) -> Bool {
        string.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private func rebuildString(from tokens: [String]) -> String {
        var result = ""

        for token in tokens {
            if token == "\n" {
                result = result.trimmingCharacters(in: .whitespaces)
                result.append("\n")
            } else {
                if result.isEmpty || result.hasSuffix("\n") {
                    result.append(token)
                } else {
                    result.append(" ")
                    result.append(token)
                }
            }
        }

        return result
    }

    // MARK: - Formatting helpers

    private func cleanupWhitespace(_ text: String) -> String {
        var result = text
        result = replace(Self.multiSpaceRegex, in: result, with: " ")
        result = replace(Self.spaceBeforePunctuationRegex, in: result, with: "$1")
        result = replace(Self.spaceAfterOpeningRegex, in: result, with: "$1")
        result = replace(Self.punctuationSpacingRegex, in: result, with: "$1 $2")
        result = replace(Self.spacesAroundNewlineRegex, in: result, with: "\n")
        result = replace(Self.excessiveNewlinesRegex, in: result, with: "\n\n")
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func capitalizeFirstLetter(of text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter }) else { return text }
        var result = text
        let capitalized = String(result[index]).uppercased()
        result.replaceSubrange(index...index, with: capitalized)
        return result
    }
}
