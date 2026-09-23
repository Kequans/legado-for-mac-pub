import Foundation
import SwiftSoup

/// 使用 macOS 的 XPath 1.0 节点查询，支持子轴、后代轴、联合及谓词函数。
/// Android JXDocument 的扩展函数不属于此引擎的兼容范围。
enum XPathRuleEvaluator {
    static func nodes(html: String, rule: String) throws -> [XMLNode] {
        var expression = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if expression.lowercased().hasPrefix("@xpath:") { expression = String(expression.dropFirst(7)) }
        guard !expression.isEmpty else { return [] }
        // 系统 tidyHTML 会丢弃 section 等 HTML5 容器；先用 SwiftSoup 整理并序列化为 XML。
        let dom = try SwiftSoup.parse(html)
        dom.outputSettings().syntax(syntax: .xml).escapeMode(.xhtml)
        let document = try XMLDocument(xmlString: dom.outerHtml(), options: [.nodeLoadExternalEntitiesNever])
        return try document.nodes(forXPath: expression)
    }

    static func values(html: String, rule: String) throws -> [String] {
        try nodes(html: html, rule: rule).map { $0.stringValue ?? "" }
    }

    static func elements(html: String, rule: String, baseURL: String = "") throws -> [SwiftSoup.Element] {
        try nodes(html: html, rule: rule).compactMap { node in
            guard node.kind == .element else { return nil }
            // XML parser 保留 td/tr 等片段，避免 HTML 片段解析丢弃表格节点。
            return try SwiftSoup.parse(node.xmlString, baseURL, Parser.xmlParser()).children().first()
        }
    }
}
