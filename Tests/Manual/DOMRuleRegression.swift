import Foundation
import SwiftSoup


func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) {
    precondition(actual == expected, "Expected \(expected), got \(actual)")
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "Regression", code: 1) }
    return value
}
@main struct DOMRuleTests {
    let html = """
    <html><head><meta property="og:novel:book_name" content="测试小说"></head>
    <body><div class="books"><a href="one" data-id="42">甲</a><a href="two">乙</a></div>
    <div class="books"><a href="three">丙</a><a href="four">丁</a></div></body></html>
    """

    func testAttributeSelectorIsNotIndex() throws {
        XCTAssertEqual(try LegadoRuleParser.value(html: html,
            rule: "[property$=book_name]@content", baseURL: "https://example.org/"), "测试小说")
    }

    func testCurrentElementAndRawAttributes() throws {
        let anchor = try XCTUnwrap(SwiftSoup.parse(html).select("a").first())
        XCTAssertEqual(try LegadoRuleParser.value(in: anchor, rule: "href", baseURL: "https://example.org/"), "one")
        XCTAssertEqual(try LegadoRuleParser.value(in: anchor, rule: "data-id"), "42")
        XCTAssertEqual(try LegadoRuleParser.value(in: anchor, rule: "abs:href", baseURL: "https://example.org/"), "https://example.org/one")
    }

    func testEachParentHasItsOwnIndex() throws {
        XCTAssertEqual(try LegadoRuleParser.values(html: html, rule: ".books@a.0@text"), ["甲", "丙"])
    }

    func testFallbackDoesNotEvaluateInvalidSecondBranch() throws {
        XCTAssertEqual(try LegadoRuleParser.value(html: html, rule: "a.0@text||[invalid@text"), "甲")
    }

    func testElementFallbackAndInterleave() throws {
        let fallback = try LegadoRuleParser.selectElements(html: html, rule: ".missing||.books@a.0")
        XCTAssertEqual(try fallback.map { try $0.text() }, ["甲", "丙"])
        let interleaved = try LegadoRuleParser.selectElements(html: html, rule: ".books.0@a%%.books.1@a")
        XCTAssertEqual(try interleaved.map { try $0.text() }, ["甲", "丙", "乙", "丁"])
    }

    func testValueListAndReplacement() throws {
        XCTAssertEqual(try LegadoRuleParser.values(html: html, rule: "a@href"), ["one", "two", "three", "four"])
        XCTAssertEqual(try LegadoRuleParser.values(html: html, rule: "a@text##甲##首"), ["首", "乙", "丙", "丁"])
    }

    func testTableCellKeepsItsContext() throws {
        let cell = try XCTUnwrap(SwiftSoup.parse("<table><tr><td>正文<span>子节点</span></td></tr></table>").select("td").first())
        XCTAssertEqual(try LegadoRuleParser.value(in: cell, rule: "ownText"), "正文")
    }
    static func main() async throws {
        setbuf(stdout, nil)
        let tests = DOMRuleTests()
        try tests.testAttributeSelectorIsNotIndex()
        try tests.testCurrentElementAndRawAttributes()
        try tests.testEachParentHasItsOwnIndex()
        try tests.testFallbackDoesNotEvaluateInvalidSecondBranch()
        try tests.testElementFallbackAndInterleave()
        try tests.testValueListAndReplacement()
        try tests.testTableCellKeepsItsContext()
        XCTAssertEqual(try LegadoRuleParser.value(html: tests.html, rule: ".books.0@a@text%%.books.1@a@text"), "甲\n丙\n乙\n丁")
        XCTAssertEqual(try LegadoRuleParser.value(html: tests.html, rule: "a.0@text&&a.1@text"), "甲\n乙")
        XCTAssertEqual(try LegadoRuleParser.values(html: tests.html, rule: "a[-1:0]@text"), ["丁", "丙", "乙", "甲"])
        let toc = "<div class='directoryArea'><p>最新</p></div><div class='directoryArea'><p><a href='1.html'>第一章</a></p><p><a href='2.html'>第二章</a></p></div>"
        let elements = try BookSourceEngine.shared.selectRuleElements(html: toc, rule: ".directoryArea.1@p", baseUrl: "https://example.org/book/")
        XCTAssertEqual(try elements.map { try LegadoRuleParser.value(in: $0, rule: "a@href") }, ["1.html", "2.html"])
        print("PASS: 11 Android DOM compatibility cases")
        try await runAdvancedRegression()
    }
}
