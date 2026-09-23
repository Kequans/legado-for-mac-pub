import Foundation
import SwiftSoup

/// Android Legado 规则的共享解析器。
///
/// 书源和 RSS 订阅源使用同一套规则语法。旧代码在两个模块各自实现了一部分
/// 解析，导致 RSS 的 CSS/JSON/JS 规则无法复用；这个类型提供统一的最小语义层。
final class LegadoRuleParser {
    private static let htmlChildSelectors: Set<String> = [
        "p", "a", "div", "span", "li", "td", "tr", "h1", "h2", "h3",
        "h4", "h5", "h6", "img", "ul", "ol", "dl", "dt", "dd", "article"
    ]

    static func value(in element: Element, rule: String, baseURL: String = "", jsLib: String? = nil) throws -> String {
        if rule.hasPrefix("@get:{"), let end = rule.firstIndex(of: "}") {
            let key = String(rule[rule.index(rule.startIndex, offsetBy: 6)..<end])
            let result = JavaScriptEngine.shared.getVariable(key)
            let suffix = String(rule[rule.index(after: end)...])
            return applyCleanRules(result, cleanRules: RegexCleaner.extractCleanRules(from: suffix).cleanRules)
        }
        if let put = rule.range(of: "@put:"), let end = rule[put.upperBound...].firstIndex(of: "}") {
            let object = String(rule[put.upperBound...end])
            let fields = try JavaScriptEngine.shared.evaluate("(" + object + ")").toDictionary() ?? [:]
            for (key, nested) in fields {
                guard let key = key as? String, let nested = nested as? String else { continue }
                JavaScriptEngine.shared.putVariable(key, value: try value(in: element, rule: nested, baseURL: baseURL, jsLib: jsLib))
            }
            let remaining = String(rule[..<put.lowerBound]) + rule[rule.index(after: end)...]
            return remaining.isEmpty ? "" : try value(in: element, rule: remaining, baseURL: baseURL, jsLib: jsLib)
        }
        if rule.contains("{{") {
            let parts = RuleTemplate.splitClean(rule)
            let expanded = try RuleTemplate.expand(parts[0]) { expression in
                if expression.hasPrefix("@") {
                    let nested = expression.hasPrefix("@js:") || expression.lowercased().hasPrefix("@xpath:") || expression.lowercased().hasPrefix("@json:")
                        ? expression : String(expression.dropFirst())
                    return try value(in: element, rule: nested, baseURL: baseURL, jsLib: jsLib)
                }
                return try JavaScriptEngine.shared.evaluateRule(expression,
                    variables: ["result": try element.outerHtml(), "baseUrl": baseURL], jsLib: jsLib)
            }
            let cleans = RegexCleaner.extractCleanRules(from: parts.dropFirst().isEmpty ? "" : "##" + parts.dropFirst().joined(separator: "##")).cleanRules
            return applyCleanRules(expanded, cleanRules: cleans)
        }
        let (mainRule, cleanRules) = RegexCleaner.extractCleanRules(from: rule)
        let segments = RuleAnalyzer.splitRule(mainRule)
        if segments.count == 1, let segment = segments.first, segment.mode == .default {
            return applyCleanRules(try LegacyRuleEvaluator.value(in: element,
                rule: cleanRulePrefix(segment.content, mode: segment.mode), baseURL: baseURL),
                cleanRules: cleanRules).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let connectorParts = splitConnector(mainRule)
        if connectorParts.parts.count > 1, let connector = connectorParts.connector {
            var results: [String] = []
            for part in connectorParts.parts {
                let result = try value(in: element, rule: part, baseURL: baseURL, jsLib: jsLib)
                if connector == .or, !result.isEmpty {
                    return applyCleanRules(result, cleanRules: cleanRules)
                }
                results.append(result)
            }
            let merged: String
            switch connector {
            case .and:
                merged = results.filter { !$0.isEmpty }.joined(separator: "\n")
            case .or:
                merged = results.first(where: { !$0.isEmpty }) ?? ""
            case .mod:
                merged = results.joined()
            }
            return applyCleanRules(merged, cleanRules: cleanRules)
        }

        var result = try element.outerHtml()

        for segment in segments {
            let cleanRule = cleanRulePrefix(segment.content, mode: segment.mode)
            switch segment.mode {
            case .js:
                result = try JavaScriptEngine.shared.parseJSRule(
                    "@js:\(cleanRule)", html: result, baseUrl: baseURL, jsLib: jsLib
                )
            case .json:
                result = try jsonValue(from: result, rule: cleanRule)
            case .xpath:
                result = try LegacyRuleEvaluator.xpathValue(html: result, rule: cleanRule, baseURL: baseURL)
            case .regex:
                result = regexValue(from: result, pattern: cleanRule)
            case .default:
                result = try LegacyRuleEvaluator.value(
                    html: result,
                    rule: cleanRule,
                    baseURL: baseURL
                )
            }
        }

        return applyCleanRules(result, cleanRules: cleanRules)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func value(html: String, rule: String, baseURL: String = "", jsLib: String? = nil) throws -> String {
        let raw = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.contains("{{"), raw.hasPrefix("{") || raw.hasPrefix("[") {
            let parts = RuleTemplate.splitClean(rule)
            let expanded = try RuleTemplate.expand(parts[0]) { expression in
                if expression.hasPrefix("$.") || expression.hasPrefix("$[") || expression.lowercased().hasPrefix("@json:") {
                    return try jsonValue(from: html, rule: expression)
                }
                return try JavaScriptEngine.shared.evaluateRule(expression,
                    variables: ["result": html, "baseUrl": baseURL], jsLib: jsLib)
            }
            return applyCleanRules(expanded, cleanRules: RegexCleaner.extractCleanRules(from: "##" + parts.dropFirst().joined(separator: "##")).cleanRules)
        }
        let document = try SwiftSoup.parse(html, baseURL)
        return try value(in: document, rule: rule, baseURL: baseURL, jsLib: jsLib)
    }

    static func values(html: String, rule: String, baseURL: String = "", jsLib: String? = nil) throws -> [String] {
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanRule.hasPrefix("/") || cleanRule.lowercased().hasPrefix("@xpath:") {
            let (main, cleans) = RegexCleaner.extractCleanRules(from: cleanRule)
            return try XPathRuleEvaluator.values(html: html, rule: main).map { applyCleanRules($0, cleanRules: cleans) }
        }
        if isJavaScriptRule(cleanRule) {
            var script = cleanRule
            if script.hasPrefix("@js:") { script = String(script.dropFirst(4)) }
            else if script.hasPrefix("<js>"), script.hasSuffix("</js>") { script = String(script.dropFirst(4).dropLast(5)) }
            return try JavaScriptEngine.shared.evaluateRuleForArray(script,
                variables: ["result": html, "html": html, "baseUrl": baseURL], jsLib: jsLib)
                .filter { !$0.isEmpty }
        }

        if isJSONRule(cleanRule) || html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let (mainRule, cleanRules) = RegexCleaner.extractCleanRules(from: cleanRule)
            let objects = try jsonValues(from: html, rule: mainRule)
            return objects.map { applyCleanRules(stringify($0), cleanRules: cleanRules) }
        }

        let (mainRule, cleanRules) = RegexCleaner.extractCleanRules(from: cleanRule)
        return try LegacyRuleEvaluator.values(html: html, rule: mainRule, baseURL: baseURL)
            .map { applyCleanRules($0, cleanRules: cleanRules) }
    }

    static func selectElements(html: String, rule: String, baseURL: String = "") throws -> [Element] {
        let (mainRule, _) = RegexCleaner.extractCleanRules(from: rule)
        let segments = RuleAnalyzer.splitRule(mainRule)
        guard let first = segments.first else { return [] }
        guard first.mode == .default || first.mode == .xpath else { return [] }

        let selectorRule = cleanRulePrefix(first.content, mode: first.mode)
        let document = try SwiftSoup.parse(html, baseURL)
        if first.mode == .xpath {
            return try LegacyRuleEvaluator.selectElements(
                in: document,
                rule: selectorRule
            )
        }

        return try LegacyRuleEvaluator.selectElements(in: document, rule: selectorRule)
    }

    static func jsonObjects(from html: String, rule: String) throws -> [[String: Any]] {
        guard let data = html.data(using: .utf8) else { throw BookSourceError.parseError }
        let object = try JSONSerialization.jsonObject(with: data)
        let (mainRule, _) = RegexCleaner.extractCleanRules(from: rule)
        return try jsonValues(from: object, rule: mainRule).compactMap { $0 as? [String: Any] }
    }

    static func jsonValue(from html: String, rule: String) throws -> String {
        guard let data = html.data(using: .utf8) else { throw BookSourceError.parseError }
        let object = try JSONSerialization.jsonObject(with: data)
        let (mainRule, cleanRules) = RegexCleaner.extractCleanRules(from: rule)
        let values = try jsonValues(from: object, rule: mainRule)
        return applyCleanRules(values.map(stringify).joined(separator: "\n"), cleanRules: cleanRules)
    }

    static func jsonDictionary(from html: String, rule: String) throws -> [String: Any]? {
        guard let data = html.data(using: .utf8) else { throw BookSourceError.parseError }
        let object = try JSONSerialization.jsonObject(with: data)
        let (mainRule, _) = RegexCleaner.extractCleanRules(from: rule)
        return try jsonValues(from: object, rule: mainRule).first as? [String: Any]
    }

    static func jsonValue(from object: [String: Any], rule: String) throws -> String {
        let (mainRule, cleanRules) = RegexCleaner.extractCleanRules(from: rule)
        let values = try jsonValues(from: object, rule: mainRule)
        guard let value = values.first else { return "" }
        return applyCleanRules(stringify(value), cleanRules: cleanRules)
    }

    // MARK: JSONPath

    private static func jsonValues(from raw: String, rule: String) throws -> [Any] {
        guard let data = raw.data(using: .utf8) else { throw BookSourceError.parseError }
        let object = try JSONSerialization.jsonObject(with: data)
        return try jsonValues(from: object, rule: rule)
    }

    private static func jsonValues(from object: Any, rule: String) throws -> [Any] {
        let connection = splitConnector(rule)
        if connection.parts.count > 1, let connector = connection.connector {
            var groups: [[Any]] = []
            for part in connection.parts {
                let result = try jsonValues(from: object, rule: part)
                if connector == .or, !result.isEmpty { return result }
                groups.append(result)
            }
            switch connector {
            case .and:
                return groups.flatMap { $0 }
            case .or:
                return groups.first(where: { !$0.isEmpty }) ?? []
            case .mod:
                var result: [Any] = []
                let maxCount = groups.map { $0.count }.max() ?? 0
                for index in 0..<maxCount {
                    for group in groups where index < group.count {
                        result.append(group[index])
                    }
                }
                return result
            }
        }
        return try JSONPathEvaluator.values(object, path: cleanRulePrefix(rule, mode: .json))
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    // MARK: HTML / rule syntax

    private static func cssValue(from html: String, rule: String, baseURL: String) throws -> String {
        let normalizedRule = normalizeCSSSelector(rule)
        if normalizedRule.isEmpty { return "" }
        let document = try SwiftSoup.parse(html, baseURL)
        let parts = splitSelectorAndChild(normalizedRule)
        var selector = parts.parent
        let index = extractIndex(from: &selector)

        let selected: Element?
        if selector.isEmpty {
            selected = try document.select("body").first()
        } else {
            let candidates = try document.select(normalizeCSSSelector(selector))
            selected = choose(candidates, index: index)
        }
        guard let selected else { return "" }

        guard let child = parts.child, !child.isEmpty else {
            return try selected.text()
        }

        let attribute = child.trimmingCharacters(in: .whitespacesAndNewlines)
        if attribute.caseInsensitiveCompare("text") == .orderedSame {
            return try selected.text()
        }
        if attribute.caseInsensitiveCompare("html") == .orderedSame {
            return try selected.html()
        }
        if htmlChildSelectors.contains(attribute.lowercased()) || attribute.contains(".") || attribute.contains("#") || attribute.contains("[") {
            let children = try selected.select(normalizeCSSSelector(attribute))
            return try children.map { try $0.outerHtml() }.joined()
        }

        let raw = try selected.attr(attribute.hasPrefix("abs:") ? String(attribute.dropFirst(4)) : attribute)
        return resolveURL(raw, baseURL: baseURL)
    }

    private static func selectElements(in document: Document, selectorRule: String) throws -> [Element] {
        let parts = splitSelectorAndChild(selectorRule)
        let parents = try document.select(normalizeCSSSelector(parts.parent))
        guard let child = parts.child, !child.isEmpty else { return Array(parents) }
        return try parents.flatMap { try $0.select(normalizeCSSSelector(child)) }
    }

    private static func splitSelectorAndChild(_ rule: String) -> (parent: String, child: String?) {
        // Legado 的 `parent@tag.li` 语法把 @ 后内容当作子选择器或属性。
        guard let at = rule.firstIndex(of: "@") else { return (rule, nil) }
        return (String(rule[..<at]), String(rule[rule.index(after: at)...]))
    }

    private static func fieldRule(_ rule: String) -> String {
        let segments = RuleAnalyzer.splitRule(rule)
        guard segments.count > 1 else { return rule }
        return segments.dropFirst().map { segment in
            let prefix: String
            switch segment.mode {
            case .js: prefix = "@js:"
            case .json: prefix = "@Json:"
            case .xpath: prefix = "@XPath:"
            case .regex: prefix = ":"
            case .default: prefix = ""
            }
            return prefix + segment.content
        }.joined(separator: "\n")
    }

    private static func extractIndex(from selector: inout String) -> Int? {
        guard let dot = selector.lastIndex(of: "."), dot != selector.startIndex else { return nil }
        let suffix = selector[selector.index(after: dot)...]
        guard let index = Int(suffix) else { return nil }
        selector = String(selector[..<dot])
        return index
    }

    private static func choose(_ elements: Elements, index: Int?) -> Element? {
        guard !elements.isEmpty else { return nil }
        guard let index else { return elements.first() }
        let normalized = index < 0 ? elements.count + index : index
        guard normalized >= 0 && normalized < elements.count else { return nil }
        return elements[normalized]
    }

    private static func normalizeCSSSelector(_ raw: String) -> String {
        var selector = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if selector.lowercased().hasPrefix("@css:") {
            selector = String(selector.dropFirst(5))
        } else if selector.hasPrefix("@@") {
            selector = String(selector.dropFirst(2))
        }
        selector = selector.replacingOccurrences(of: #"class\.([a-zA-Z0-9_-]+)"#, with: ".$1", options: .regularExpression)
        selector = selector.replacingOccurrences(of: #"id\.([a-zA-Z0-9_-]+)"#, with: "#$1", options: .regularExpression)
        selector = selector.replacingOccurrences(of: #"tag\.([a-zA-Z0-9_-]+)"#, with: "$1", options: .regularExpression)
        return selector.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func xpathToCSSRule(_ raw: String) -> String {
        var rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.hasPrefix("@XPath:") { rule = String(rule.dropFirst(7)) }
        var attribute: String?
        if let range = rule.range(of: "/@", options: .backwards) {
            attribute = String(rule[range.upperBound...])
            rule = String(rule[..<range.lowerBound])
        }
        let components = rule.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." }
        var css = components.last ?? rule
        if let match = try? NSRegularExpression(pattern: #"^([\w-]+)\[@id=['\"]([^'\"]+)['\"]\]$"#),
           let result = match.firstMatch(in: css, range: NSRange(location: 0, length: css.utf16.count)) {
            let ns = css as NSString
            css = "\(ns.substring(with: result.range(at: 1)))#\(ns.substring(with: result.range(at: 2)))"
        } else if let match = try? NSRegularExpression(pattern: #"^([\w-]+)\[@class=['\"]([^'\"]+)['\"]\]$"#),
                  let result = match.firstMatch(in: css, range: NSRange(location: 0, length: css.utf16.count)) {
            let ns = css as NSString
            let classes = ns.substring(with: result.range(at: 2)).split(separator: " ").map { ".\($0)" }.joined()
            css = "\(ns.substring(with: result.range(at: 1)))\(classes)"
        }
        if let attribute { return "\(css)@\(attribute)" }
        return css
    }

    private static func regexValue(from input: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return "" }
        let range = NSRange(location: 0, length: input.utf16.count)
        guard let match = regex.firstMatch(in: input, range: range) else { return "" }
        let ns = input as NSString
        if match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
            return ns.substring(with: match.range(at: 1))
        }
        return ns.substring(with: match.range)
    }

    private static func applyCleanRules(_ input: String, cleanRules: [(pattern: String, replacement: String)]) -> String {
        var result = input
        for cleanRule in cleanRules {
            guard let regex = try? NSRegularExpression(pattern: cleanRule.pattern, options: [.dotMatchesLineSeparators]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: cleanRule.replacement
            )
        }
        return result
    }

    private static func cleanRulePrefix(_ rule: String, mode: RuleAnalyzer.RuleMode) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .default:
            if trimmed.lowercased().hasPrefix("@css:") { return String(trimmed.dropFirst(5)) }
            if trimmed.hasPrefix("@@") { return String(trimmed.dropFirst(2)) }
        case .json:
            if trimmed.lowercased().hasPrefix("@json:") { return String(trimmed.dropFirst(6)) }
        case .xpath:
            if trimmed.lowercased().hasPrefix("@xpath:") { return String(trimmed.dropFirst(7)) }
        case .regex:
            if trimmed.hasPrefix(":") { return String(trimmed.dropFirst()) }
        case .js:
            break
        }
        return trimmed
    }

    private static func isJSONRule(_ rule: String) -> Bool {
        let lower = rule.lowercased()
        return rule.hasPrefix("$." ) || rule.hasPrefix("$[") || lower.hasPrefix("@json:")
    }

    private static func isJavaScriptRule(_ rule: String) -> Bool {
        rule.hasPrefix("@js:") || rule.hasPrefix("<js>") || (rule.hasPrefix("{{") && rule.contains("@js"))
    }

    private static func splitConnector(_ rule: String) -> (parts: [String], connector: RuleConnector.ConnectorType?) {
        var parts: [String] = []
        var current = ""
        var connector: RuleConnector.ConnectorType?
        var bracketDepth = 0
        var quote: Character?
        var index = rule.startIndex

        while index < rule.endIndex {
            let character = rule[index]
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                index = rule.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                index = rule.index(after: index)
                continue
            }
            if character == "(" || character == "[" || character == "{" {
                bracketDepth += 1
                current.append(character)
                index = rule.index(after: index)
                continue
            }
            if character == ")" || character == "]" || character == "}" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
                index = rule.index(after: index)
                continue
            }

            if bracketDepth == 0, index < rule.index(before: rule.endIndex) {
                let next = rule[rule.index(after: index)]
                let detected: RuleConnector.ConnectorType?
                if character == "&" && next == "&" {
                    detected = .and
                } else if character == "|" && next == "|" {
                    detected = .or
                } else if character == "%" && next == "%" {
                    detected = .mod
                } else {
                    detected = nil
                }
                if let detected {
                    if connector == nil { connector = detected }
                    if connector == detected {
                        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                        current = ""
                        index = rule.index(index, offsetBy: 2)
                        continue
                    }
                }
            }
            current.append(character)
            index = rule.index(after: index)
        }

        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return (parts.filter { !$0.isEmpty }, connector)
    }

    private static func resolveURL(_ value: String, baseURL: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let base = URL(string: baseURL), let url = URL(string: trimmed, relativeTo: base) else { return trimmed }
        return url.absoluteURL.absoluteString
    }
}
