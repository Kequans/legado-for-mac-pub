import Foundation
import CoreFoundation

/// 常用 JSONPath：递归属性、联合索引、切片和简单比较过滤；未知语法显式报错。
enum JSONPathEvaluator {
    enum Step { case key(String), recursive(String), bracket(String) }

    static func values(_ root: Any, path raw: String) throws -> [Any] {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.lowercased().hasPrefix("@json:") { path = String(path.dropFirst(6)) }
        if path.hasPrefix("$") { path.removeFirst() }
        var steps: [Step] = []
        var index = path.startIndex
        while index < path.endIndex {
            if path[index...].hasPrefix("..") {
                index = path.index(index, offsetBy: 2)
                let start = index
                while index < path.endIndex && path[index] != "." && path[index] != "[" { index = path.index(after: index) }
                guard start != index else { throw unsupported(raw) }
                steps.append(.recursive(String(path[start..<index])))
            } else if path[index] == "." {
                index = path.index(after: index)
            } else if path[index] == "[" {
                index = path.index(after: index)
                let start = index
                var depth = 1
                var quote: Character?
                var escaped = false
                while index < path.endIndex {
                    let char = path[index]
                    if let active = quote {
                        if escaped { escaped = false }
                        else if char == "\\" { escaped = true }
                        else if char == active { quote = nil }
                    } else if char == "'" || char == "\"" { quote = char }
                    else if char == "[" { depth += 1 }
                    else if char == "]" { depth -= 1; if depth == 0 { break } }
                    index = path.index(after: index)
                }
                guard index < path.endIndex else { throw unsupported(raw) }
                steps.append(.bracket(String(path[start..<index])))
                index = path.index(after: index)
            } else {
                let start = index
                while index < path.endIndex && path[index] != "." && path[index] != "[" { index = path.index(after: index) }
                steps.append(.key(String(path[start..<index])))
            }
        }
        var current: [Any] = [root]
        for step in steps {
            current = try current.flatMap { item -> [Any] in
                switch step {
                case .key(let key): return children(item, key: key)
                case .recursive(let key):
                    var matches = children(item, key: key)
                    let nested = (item as? [Any]) ?? (item as? [String: Any]).map { Array($0.values) } ?? []
                    for child in nested { matches += try descend(child, key: key) }
                    return matches
                case .bracket(let body): return try bracket(item, body: body)
                }
            }
        }
        return current
    }

    private static func children(_ item: Any, key: String) -> [Any] {
        if key == "*" { return (item as? [Any]) ?? (item as? [String: Any]).map { Array($0.values) } ?? [] }
        return (item as? [String: Any])?[key].map { [$0] } ?? []
    }
    private static func descend(_ item: Any, key: String) throws -> [Any] {
        var result = children(item, key: key)
        for child in (item as? [Any]) ?? (item as? [String: Any]).map({ Array($0.values) }) ?? [] {
            result += try descend(child, key: key)
        }
        return result
    }
    private static func bracket(_ item: Any, body: String) throws -> [Any] {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body == "*" { return children(item, key: "*") }
        if body.hasPrefix("?(") && body.hasSuffix(")") {
            return try children(item, key: "*").filter { try matches($0, expression: String(body.dropFirst(2).dropLast())) }
        }
        let union = split(body, separator: ",")
        if union.count > 1 { return try union.flatMap { try bracket(item, body: $0) } }
        if (body.hasPrefix("'") && body.hasSuffix("'")) || (body.hasPrefix("\"") && body.hasSuffix("\"")) {
            return children(item, key: String(body.dropFirst().dropLast()))
        }
        guard let array = item as? [Any] else { return [] }
        if let index = Int(body) {
            let normalized = index < 0 ? array.count + index : index
            return array.indices.contains(normalized) ? [array[normalized]] : []
        }
        let slice = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(slice.count), slice.allSatisfy({ $0.isEmpty || Int($0) != nil }) else { throw unsupported(body) }
        let step = slice.count == 3 ? Int(slice[2]) ?? 1 : 1
        guard step != 0 else { throw unsupported(body) }
        func bound(_ part: Substring, fallback: Int) -> Int {
            guard let value = Int(part) else { return fallback }
            let value1 = value < 0 ? array.count + value : value
            return step > 0 ? min(max(0, value1), array.count) : min(max(-1, value1), array.count - 1)
        }
        let start = bound(slice[0], fallback: step > 0 ? 0 : array.count - 1)
        let end = bound(slice[1], fallback: step > 0 ? array.count : -1)
        return stride(from: start, to: end, by: step).filter { array.indices.contains($0) }.map { array[$0] }
    }

    private static func matches(_ item: Any, expression: String) throws -> Bool {
        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        for op in ["||", "&&"] {
            let parts = split(expr, separator: op)
            if parts.count > 1 {
                for part in parts {
                    let result = try matches(item, expression: part)
                    if op == "||" && result { return true }
                    if op == "&&" && !result { return false }
                }
                return op == "&&"
            }
        }
        if expr.hasPrefix("(") && expr.hasSuffix(")") { return try matches(item, expression: String(expr.dropFirst().dropLast())) }
        for op in ["==", "!=", "<=", ">=", "<", ">"] {
            let parts = split(expr, separator: op)
            if parts.count == 2 {
                guard let left = try operand(item, text: parts[0]), let right = try operand(item, text: parts[1]) else { return false }
                if op == "==" { return equal(left, right) }
                if op == "!=" { return !equal(left, right) }
                guard let a = left as? NSNumber, let b = right as? NSNumber,
                      CFGetTypeID(a) != CFBooleanGetTypeID(), CFGetTypeID(b) != CFBooleanGetTypeID() else { return false }
                switch op {
                case "<": return a.doubleValue < b.doubleValue
                case ">": return a.doubleValue > b.doubleValue
                case "<=": return a.doubleValue <= b.doubleValue
                default: return a.doubleValue >= b.doubleValue
                }
            }
        }
        guard expr.hasPrefix("@") else { throw unsupported(expr) }
        return try !values(item, path: "$" + expr.dropFirst()).isEmpty
    }

    private static func operand(_ item: Any, text: String) throws -> Any? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { return try values(item, path: "$" + value.dropFirst()).first }
        if value.hasPrefix("'") && value.hasSuffix("'") { return String(value.dropFirst().dropLast()) }
        guard let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw unsupported(value)
        }
        return object
    }
    private static func equal(_ a: Any, _ b: Any) -> Bool {
        if a is NSNull { return b is NSNull }
        if let x = a as? NSNumber, let y = b as? NSNumber {
            return (CFGetTypeID(x) == CFBooleanGetTypeID()) == (CFGetTypeID(y) == CFBooleanGetTypeID()) && x == y
        }
        if let x = a as? String, let y = b as? String { return x == y }
        return false
    }

    private static func split(_ text: String, separator: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        var index = start
        var quote: Character?
        var escaped = false
        var depth = 0
        while index < text.endIndex {
            let char = text[index]
            if let active = quote {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == active { quote = nil }
            } else if char == "'" || char == "\"" { quote = char }
            else if char == "(" || char == "[" { depth += 1 }
            else if char == ")" || char == "]" { depth -= 1 }
            else if depth == 0 && text[index...].hasPrefix(separator) {
                result.append(String(text[start..<index]))
                index = text.index(index, offsetBy: separator.count)
                start = index
                continue
            }
            index = text.index(after: index)
        }
        result.append(String(text[start...]))
        return result
    }
    private static func unsupported(_ value: String) -> SourceRequestError { .unsupported("JSONPath: \(value)") }
}
