import Foundation
import SwiftSoup

/// 对齐 Android Legado JSOUP 规则的本地 evaluator。
///
/// SwiftSoup 负责 DOM 操作，本类型补上 Legado 的 class.xxx、tag.xxx、
/// children、索引/区间、textNodes、ownText、all 和连接链语义。
final class LegacyRuleEvaluator {
    private typealias XPathStep = (name: String, predicate: String?)
    private enum IndexToken {
        case index(Int)
        case range(Int?, Int?, Int)
    }

    private struct SelectionSpec {
        let selector: String
        let tokens: [IndexToken]
        let excludes: Bool
    }

    private static let valueTokens: Set<String> = [
        "text", "textnodes", "owntext", "html", "all"
    ]

    static func value(html: String, rule: String, baseURL: String = "") throws -> String {
        let document = try SwiftSoup.parse(html, baseURL)
        return try value(in: document, rule: rule, baseURL: baseURL)
    }

    static func value(in root: Element, rule: String, baseURL: String = "") throws -> String {
        try values(in: root, rule: rule, baseURL: baseURL).joined(separator: "\n")
    }

    static func values(html: String, rule: String, baseURL: String = "") throws -> [String] {
        let document = try SwiftSoup.parse(html, baseURL)
        return try values(in: document, rule: rule, baseURL: baseURL)
    }

    static func values(in root: Element, rule: String, baseURL: String = "") throws -> [String] {
        let connection = splitConnector(rule)
        if connection.parts.count > 1, let connector = connection.connector {
            var groupedValues: [[String]] = []
            for part in connection.parts {
                let result = try values(in: root, rule: part, baseURL: baseURL)
                if !result.isEmpty { groupedValues.append(result) }
                if connection.connector == .or, !result.isEmpty { return result }
            }
            switch connector {
            case .and:
                return groupedValues.flatMap { $0 }
            case .or:
                return groupedValues.first(where: { !$0.isEmpty }) ?? []
            case .mod:
                var result: [String] = []
                let maxCount = groupedValues.first?.count ?? 0
                for index in 0..<maxCount {
                    for group in groupedValues where index < group.count {
                        result.append(group[index])
                    }
                }
                return result
            }
        }
        let stages = splitStages(rule)
        guard let terminal = stages.last else { return [] }
        var elements: [Element] = [root]
        for stage in stages.dropLast() {
            elements = try select(elements, stage)
        }
        // Android treats the last stage as text/HTML or an arbitrary attribute name.
        return try extractList(elements, token: terminal, baseURL: baseURL)
    }

    static func selectElements(html: String, rule: String, baseURL: String = "") throws -> [Element] {
        let document = try SwiftSoup.parse(html, baseURL)
        return try selectElements(in: document, rule: rule)
    }

    static func selectElements(in root: Element, rule: String) throws -> [Element] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.lowercased().hasPrefix("@xpath:") {
            return try xpathElements(in: root, rule: trimmed)
        }
        let connection = splitConnector(rule)
        if connection.parts.count > 1, let connector = connection.connector {
            var groups: [[Element]] = []
            for part in connection.parts {
                let selected = try selectElements(in: root, rule: part)
                if connector == .or, !selected.isEmpty { return selected }
                groups.append(selected)
            }
            if connector == .mod {
                return (0..<(groups.first?.count ?? 0)).flatMap { index in
                    groups.compactMap { index < $0.count ? $0[index] : nil }
                }
            }
            return groups.flatMap { $0 }
        }
        let stages = splitStages(rule)
        guard !stages.isEmpty else { return [] }
        var elements: [Element] = [root]
        for stage in stages {
            if isValueToken(stage) || stage.isEmpty { break }
            elements = try select(elements, stage)
        }
        return elements
    }

    static func xpathValue(html: String, rule: String, baseURL: String = "") throws -> String {
        try XPathRuleEvaluator.values(html: html, rule: rule).joined(separator: "\n")
    }

    static func xpathElements(in root: Element, rule: String) throws -> [Element] {
        try XPathRuleEvaluator.elements(html: root.outerHtml(), rule: rule)
    }

    // MARK: - Selection

    private static func select(_ roots: [Element], _ rawStage: String) throws -> [Element] {
        let spec = parseSelection(rawStage)
        if spec.selector.isEmpty || spec.selector.caseInsensitiveCompare("children") == .orderedSame {
            return roots.flatMap { applyIndex($0.children().array(), spec) }
        }

        var candidates: [Element] = []
        for root in roots {
            let selector = normalizeSelector(spec.selector)
            let selected: Elements
            if spec.selector.lowercased().hasPrefix("text.") {
                selected = try root.getElementsContainingOwnText(
                    String(spec.selector.dropFirst(5))
                )
            } else if spec.selector.lowercased().hasPrefix("class.") {
                selected = try root.getElementsByClass(
                    String(spec.selector.dropFirst(6))
                )
            } else if spec.selector.lowercased().hasPrefix("tag.") {
                selected = try root.getElementsByTag(
                    String(spec.selector.dropFirst(4))
                )
            } else if spec.selector.lowercased().hasPrefix("id.") {
                selected = try root.select("#\(String(spec.selector.dropFirst(3)))")
            } else {
                selected = try root.select(selector)
            }
            candidates.append(contentsOf: applyIndex(selected.array(), spec))
        }
        return candidates
    }

    private static func parseSelection(_ raw: String) -> SelectionSpec {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("@css:") {
            value = String(value.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if value.hasPrefix("@@") {
            value = String(value.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var selector = value
        var body: String?
        var excludes = false

        if value.hasSuffix("]"), let open = value.lastIndex(of: "["),
           value[value.index(after: open)..<value.index(before: value.endIndex)]
            .range(of: #"^!?[\d\s,:+\-]+$"#, options: .regularExpression) != nil {
            selector = String(value[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
            body = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        } else if let bang = value.firstIndex(of: "!"),
                  !value[..<bang].isEmpty,
                  !parseIndexTokens(String(value[value.index(after: bang)...])).isEmpty {
            selector = String(value[..<bang]).trimmingCharacters(in: .whitespacesAndNewlines)
            body = String(value[value.index(after: bang)...])
            excludes = true
        } else if value.hasPrefix("."),
                  !parseIndexTokens(String(value.dropFirst())).isEmpty {
            selector = ""
            body = String(value.dropFirst())
        } else if let dot = value.lastIndex(of: "."),
                  !value[..<dot].isEmpty,
                  !parseIndexTokens(String(value[value.index(after: dot)...])).isEmpty {
            selector = String(value[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
            body = String(value[value.index(after: dot)...])
        }

        if let body, body.hasPrefix("!") {
            excludes = true
        }
        let normalizedBody = body?.drop(while: { $0 == "!" || $0.isWhitespace }) ?? ""
        let tokens = parseIndexTokens(String(normalizedBody))
        return SelectionSpec(selector: selector, tokens: tokens, excludes: excludes)
    }

    private static func parseIndexTokens(_ value: String) -> [IndexToken] {
        guard !value.isEmpty else { return [] }
        return value.split(separator: ",", omittingEmptySubsequences: false).compactMap { raw in
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = token.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 1, let index = Int(parts[0]) {
                return .index(index)
            }
            guard parts.count == 2 || parts.count == 3 else { return nil }
            let start = parts[0].isEmpty ? nil : Int(parts[0])
            let end = parts[1].isEmpty ? nil : Int(parts[1])
            let step = parts.count == 3 && !parts[2].isEmpty ? Int(parts[2]) ?? 1 : 1
            guard start != nil || end != nil else { return nil }
            return .range(start, end, step == 0 ? 1 : step)
        }
    }

    private static func applyIndex(_ elements: [Element], _ spec: SelectionSpec) -> [Element] {
        guard !spec.tokens.isEmpty else { return elements }
        guard !elements.isEmpty else { return [] }
        var indexes: [Int] = []

        func normalized(_ value: Int) -> Int {
            let value = value < 0 ? elements.count + value : value
            return min(max(value, 0), elements.count - 1)
        }

        for token in spec.tokens {
            switch token {
            case .index(let index):
                let index = index < 0 ? elements.count + index : index
                if index >= 0 && index < elements.count { indexes.append(index) }
            case .range(let startValue, let endValue, let stepValue):
                let start = normalized(startValue ?? 0)
                let end = normalized(endValue ?? (elements.count - 1))
                let step = max(1, abs(stepValue))
                if start <= end {
                    indexes.append(contentsOf: stride(from: start, through: end, by: step))
                } else {
                    indexes.append(contentsOf: stride(from: start, through: end, by: -step))
                }
            }
        }

        var seen = Set<Int>()
        let unique = indexes.filter { seen.insert($0).inserted }
        if spec.excludes {
            let excluded = Set(unique)
            return elements.enumerated().compactMap { excluded.contains($0.offset) ? nil : $0.element }
        }
        return unique.map { elements[$0] }
    }

    private static func normalizeSelector(_ raw: String) -> String {
        var selector = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        selector = selector.replacingOccurrences(of: #"class\.([a-zA-Z0-9_-]+)"#, with: ".$1", options: .regularExpression)
        selector = selector.replacingOccurrences(of: #"id\.([a-zA-Z0-9_-]+)"#, with: "#$1", options: .regularExpression)
        selector = selector.replacingOccurrences(of: #"tag\.([a-zA-Z0-9_-]+)"#, with: "$1", options: .regularExpression)
        return selector
    }

    private static func splitStages(_ raw: String) -> [String] {
        var rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.lowercased().hasPrefix("@css:") {
            rule = String(rule.dropFirst(5))
        } else if rule.hasPrefix("@@") {
            rule = String(rule.dropFirst(2))
        }

        var stages: [String] = []
        var current = ""
        var bracketDepth = 0
        var quote: Character?
        for character in rule {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "[" {
                bracketDepth += 1
                current.append(character)
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            } else if character == "@" && bracketDepth == 0 {
                stages.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }
        stages.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return stages.filter { !$0.isEmpty }
    }

    private static func cleanXPath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("@xpath:") {
            value = String(value.dropFirst(7))
        }
        return value
    }

    private static func splitConnector(_ raw: String) -> (parts: [String], connector: RuleConnector.ConnectorType?) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var depth = 0
        var quote: Character?
        var current = ""
        var parts: [String] = []
        var connector: RuleConnector.ConnectorType?
        var index = value.startIndex

        while index < value.endIndex {
            let character = value[index]
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                index = value.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                index = value.index(after: index)
                continue
            }
            if character == "[" || character == "(" || character == "{" {
                depth += 1
                current.append(character)
                index = value.index(after: index)
                continue
            }
            if character == "]" || character == ")" || character == "}" {
                depth = max(0, depth - 1)
                current.append(character)
                index = value.index(after: index)
                continue
            }
            if depth == 0, index < value.index(before: value.endIndex) {
                let next = value[value.index(after: index)]
                let candidate: RuleConnector.ConnectorType?
                if character == "&" && next == "&" {
                    candidate = .and
                } else if character == "|" && next == "|" {
                    candidate = .or
                } else if character == "%" && next == "%" {
                    candidate = .mod
                } else {
                    candidate = nil
                }
                if let candidate, connector == nil { connector = candidate }
                if let candidate, connector == candidate {
                    parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                    current = ""
                    index = value.index(index, offsetBy: 2)
                    continue
                }
            }
            current.append(character)
            index = value.index(after: index)
        }
        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return (parts.filter { !$0.isEmpty }, connector)
    }

    private static func xpathSteps(_ raw: String) -> [(name: String, predicate: String?)] {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var result: [XPathStep] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in value {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "[" {
                depth += 1
                current.append(character)
            } else if character == "]" {
                depth = max(0, depth - 1)
                current.append(character)
            } else if character == "/" && depth == 0 {
                appendXPathStep(current, to: &result)
                current = ""
            } else {
                current.append(character)
            }
        }
        appendXPathStep(current, to: &result)
        return result
    }

    private static func appendXPathStep(
        _ raw: String,
        to result: inout [XPathStep]
    ) {
        let step = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty, step != "." else { return }
        guard let open = step.firstIndex(of: "["), step.hasSuffix("]") else {
            result.append((step, nil))
            return
        }
        result.append((
            String(step[..<open]),
            String(step[step.index(after: open)..<step.index(before: step.endIndex)])
        ))
    }

    private static func applyXPathPredicate(_ candidates: Elements, _ predicate: String?) -> [Element] {
        guard let predicate, !predicate.isEmpty else { return Array(candidates) }
        if let index = Int(predicate) {
            let normalized = index > 0 ? index - 1 : candidates.count + index
            return normalized >= 0 && normalized < candidates.count ? [candidates[normalized]] : []
        }
        if let regex = try? NSRegularExpression(
            pattern: #"^@([\w:-]+)\s*=\s*['\"]([^'\"]*)['\"]$"#
        ), let match = regex.firstMatch(in: predicate, range: NSRange(location: 0, length: predicate.utf16.count)) {
            let value = predicate as NSString
            let attribute = value.substring(with: match.range(at: 1))
            let expected = value.substring(with: match.range(at: 2))
            return candidates.array().filter { (try? $0.attr(attribute)) == expected }
        }
        if let regex = try? NSRegularExpression(
            pattern: #"^text\(\)\s*=\s*['\"]([^'\"]*)['\"]$"#
        ), let match = regex.firstMatch(in: predicate, range: NSRange(location: 0, length: predicate.utf16.count)) {
            let value = predicate as NSString
            let expected = value.substring(with: match.range(at: 1))
            return candidates.array().filter { (try? $0.text()) == expected }
        }
        if let regex = try? NSRegularExpression(
            pattern: #"^position\(\)\s*>\s*(\d+)$"#
        ), let match = regex.firstMatch(in: predicate, range: NSRange(location: 0, length: predicate.utf16.count)) {
            let value = predicate as NSString
            let lowerBound = (Int(value.substring(with: match.range(at: 1))) ?? 0)
            return Array(candidates.array().dropFirst(lowerBound))
        }
        return Array(candidates)
    }

    // MARK: - Values

    private static func extract(_ elements: [Element], token: String, baseURL: String) throws -> String {
        try extractList(elements, token: token, baseURL: baseURL).joined(separator: "\n")
    }

    private static func extractList(_ elements: [Element], token: String, baseURL: String) throws -> [String] {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let lower = token.lowercased()
        if lower == "text" {
            return try elements.map { try $0.text() }.filter { !$0.isEmpty }
        }
        if lower == "textnodes" {
            return elements.map {
                $0.textNodes().map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }.filter { !$0.isEmpty }
        }
        if lower == "owntext" {
            return elements.map { $0.ownText() }.filter { !$0.isEmpty }
        }
        if lower == "html" {
            return try elements.map { element in
                let document = try SwiftSoup.parse(try element.outerHtml())
                try document.select("script, style").remove()
                return try document.select("body").first()?.html() ?? element.html()
            }.filter { !$0.isEmpty }
        }
        if lower == "all" {
            return try elements.map { try $0.outerHtml() }
        }

        var result: [String] = []
        for element in elements {
            let raw = try element.attr(token.hasPrefix("abs:") ? String(token.dropFirst(4)) : token)
            let value = token.hasPrefix("abs:") ? resolveURL(raw, baseURL: baseURL) : raw
            if !value.isEmpty, !result.contains(value) { result.append(value) }
        }
        return result
    }

    private static func isValueToken(_ raw: String) -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        return valueTokens.contains(token) || token.hasPrefix("abs:")
            || ["href", "src", "content", "data-src", "title"].contains(token)
    }

    private static func looksLikeSelector(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.contains(".") || value.contains("#")
            || value.contains("[") || value.hasPrefix("class")
            || value.hasPrefix("tag") || value.hasPrefix("id")
            || value.hasPrefix("text") || value == "children"
            || value.range(of: #"^[a-zA-Z][a-zA-Z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func resolveURL(_ value: String, baseURL: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let base = URL(string: baseURL), let url = URL(string: trimmed, relativeTo: base) else {
            return trimmed
        }
        return url.absoluteURL.absoluteString
    }
}
