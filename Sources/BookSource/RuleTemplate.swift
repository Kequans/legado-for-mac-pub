import Foundation

/// 模板边界扫描：保留模板内部的 ##、引号、转义和 JS 对象花括号。
enum RuleTemplate {
    struct Part {
        let range: Range<String.Index>
        let expression: String
    }
    static func parts(_ text: String) throws -> [Part] {
        var result: [Part] = []
        var cursor = text.startIndex
        while let open = text.range(of: "{{", range: cursor..<text.endIndex) {
            var index = open.upperBound
            let start = index
            var depth = 0
            var quote: Character?
            var escaped = false
            var closed = false
            while index < text.endIndex {
                let char = text[index]
                if let active = quote {
                    if escaped { escaped = false }
                    else if char == "\\" { escaped = true }
                    else if char == active { quote = nil }
                } else if char == "\"" || char == "'" || char == "`" {
                    quote = char
                } else if char == "}" && depth == 0 && text[index...].hasPrefix("}}") {
                    let end = text.index(index, offsetBy: 2)
                    result.append(Part(range: open.lowerBound..<end, expression: String(text[start..<index])))
                    cursor = end
                    closed = true
                    break
                } else if char == "{" { depth += 1 }
                else if char == "}" { depth -= 1 }
                index = text.index(after: index)
            }
            guard closed else { throw SourceRequestError.unsupported("未闭合的 {{...}} 模板") }
        }
        return result
    }

    static func expand(_ text: String, evaluate: (String) throws -> String) throws -> String {
        var output = ""
        var cursor = text.startIndex
        for part in try parts(text) {
            output += text[cursor..<part.range.lowerBound]
            output += try evaluate(part.expression.trimmingCharacters(in: .whitespacesAndNewlines))
            cursor = part.range.upperBound
        }
        output += text[cursor...]
        return output
    }

    static func splitClean(_ text: String) -> [String] {
        let templates = (try? parts(text)) ?? []
        var result: [String] = []
        var start = text.startIndex
        var index = start
        while index < text.endIndex {
            if let part = templates.first(where: { $0.range.lowerBound == index }) {
                index = part.range.upperBound
                continue
            }
            if text[index...].hasPrefix("##") {
                result.append(String(text[start..<index]))
                index = text.index(index, offsetBy: 2)
                start = index
            } else { index = text.index(after: index) }
        }
        result.append(String(text[start...]))
        return result
    }
}
