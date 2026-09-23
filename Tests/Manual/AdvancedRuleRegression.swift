import Foundation

private func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
}

/// 所有响应均由内存 URLProtocol 提供；不发起公网请求、不访问用户数据库。
final class RuleFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var paths: [String] = []
    nonisolated(unsafe) static var retries = 0
    private var pending: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.lock.lock()
        Self.paths.append(path)
        if path == "/retry" { Self.retries += 1 }
        let retry = Self.retries
        Self.lock.unlock()
        if path == "/slow" {
            let work = DispatchWorkItem { [weak self] in self?.reply("late", final: "https://fixture.test/slow") }
            pending = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: work)
            return
        }
        switch path {
        case "/search":
            reply("<div class='book'><a href='info'>测试书</a></div>", final: "https://fixture.test/mirror/book/")
        case "/info":
            reply("<h1>测试书</h1><a class='toc' href='toc/'>目录</a>", final: "https://fixture.test/mirror/book/info")
        case "/toc":
            reply("<a class='chapter' href='one'>一</a><option value='two'>2</option><option value='three'>3</option><option value='two'>2</option>", final: "https://fixture.test/mirror/toc/")
        case "/mirror/toc/two":
            reply("<a class='chapter' href='one'>重复</a><a class='chapter' href='second'>二</a><option value='./'>循环</option>", final: request.url!.absoluteString)
        case "/mirror/toc/three":
            reply("<a class='chapter' href='third'>三</a>", final: request.url!.absoluteString)
        case "/content":
            reply("<div class='article'><p>正文一</p></div><option value='two'>2</option><option value='three'>3</option>", final: "https://fixture.test/mirror/content/")
        case "/mirror/content/two":
            reply("<div class='article'><p>正文二</p></div><option value='./'>循环</option>", final: request.url!.absoluteString)
        case "/mirror/content/three":
            reply("<div class='article'><p>正文三</p></div>", final: request.url!.absoluteString)
        case "/retry": reply("ok", final: request.url!.absoluteString, status: retry < 2 ? 503 : 200)
        default: reply("unknown", final: request.url!.absoluteString, status: 404)
        }
    }
    private func reply(_ text: String, final: String, status: Int = 200) {
        let response = HTTPURLResponse(url: URL(string: final)!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { pending?.cancel() }
}

func runAdvancedRegression() async throws {
    // 模板内净化不能被外层 ## 分割；JS 字符串中的 }} 不能提前结束模板。
    let expanded = try BookSourceEngine.shared.parseRuleValue(html: "<div class='intro'>简介广告</div>",
        rule: "🔖 {{@.intro@text##广告##}}{{'\\n'}}{{'}}'}}", baseUrl: "https://fixture.test/")
    check(expanded == "🔖 简介\n}}", "nested template cleanup: \(expanded)")

    let json = """
    {"books":[{"name":"A","price":1},{"name":"B","price":5},{"name":"C","price":9}],"nested":{"books":[{"name":"D"}]},"a.b":"quoted"}
    """
    check(tryValueList(json, "$['a.b']") == ["quoted"], "quoted property")
    check(tryValueList(json, "$.books[0,2].name") == ["A", "C"], "union")
    check(tryValueList(json, "$.books[0:2].name") == ["A", "B"], "exclusive slice end")
    check(tryValueList(json, "$.books[::-1].name") == ["C", "B", "A"], "reverse slice")
    check(tryValueList(json, "$.books[?(@.price >= 5 && @.name != 'C')].name") == ["B"], "filter")
    check(Set(tryValueList(json, "$..books[*].name")) == Set(["A", "B", "C", "D"]), "recursive path")

    let html = "<div id='toc'><a href='1'>一</a><section><a href='2'>二</a></section><a href='3'>三</a></div>"
    check(try LegadoRuleParser.values(html: html, rule: "@XPath://div[@id='toc']/a/@href") == ["1", "3"], "child axis")
    check(try LegadoRuleParser.values(html: html, rule: "@XPath://div[@id='toc']//a[contains(@href,'2')]/text()") == ["二"], "descendant predicate")
    check(try LegadoRuleParser.values(html: html, rule: "@XPath://div/a[last()]/@href") == ["3"], "last predicate")

    let configured = try SourceRequest.parse("/search,{\"method\":\"POST\",\"body\":\"q={{key}}&page={{page+1}}\",\"headers\":{\"X-Test\":\"ok\"},\"retry\":2}",
        baseURL: "https://fixture.test/", keyword: "甲 &乙")
    check(configured.request.httpMethod == "POST", "POST")
    check(String(data: configured.request.httpBody!, encoding: .utf8) == "q=%E7%94%B2%20%26%E4%B9%99&page=2", "form encoding")
    check(configured.request.value(forHTTPHeaderField: "X-Test") == "ok" && configured.retries == 2, "request config")
    do {
        _ = try SourceRequest.parse("/,{\"webView\":true}", baseURL: "https://fixture.test/")
        preconditionFailure("WebView must fail explicitly")
    } catch SourceRequestError.unsupported { }

    async let first: String = JavaScriptEngine.withScope {
        _ = try JavaScriptEngine.shared.evaluate("java.put('id', 'A');\n'A'")
        try await Task.sleep(nanoseconds: 20_000_000)
        return try JavaScriptEngine.shared.evaluateRule("java.get('id')")
    }
    async let second: String = JavaScriptEngine.withScope {
        _ = try JavaScriptEngine.shared.evaluate("java.put('id', 'B');\n'B'")
        return try JavaScriptEngine.shared.evaluateRule("java.get('id')")
    }
    let (a,b) = try await (first, second)
    check(a == "A" && b == "B", "isolated JS caches")
    let seed = try await JavaScriptEngine.withScope {
        _ = try JavaScriptEngine.shared.evaluate("java.put('persist', '值');\n'值'")
        return JavaScriptEngine.shared.savedVariables
    }
    let restored = try await JavaScriptEngine.withScope(seed: seed) {
        try JavaScriptEngine.shared.evaluateRule("java.get('persist')")
    }
    check(restored == "值", "persisted rule variables")
    check(try JavaScriptEngine.shared.evaluateRule("'abc'.match(/b/)[0]") == "b", "native String.match")
    do {
        _ = try JavaScriptEngine.shared.evaluate("new JavaImporter()")
        preconditionFailure("Java extension must fail explicitly")
    } catch BookSourceError.unsupportedJavaScriptInRule { }

    let stored = try await JavaScriptEngine.withScope {
        let result = try LegadoRuleParser.value(html: "<h1>书名</h1><a data-id='123'></a>", rule: "h1@text@put:{bid:'a@data-id'}")
        check(result == "书名", "inline put result")
        return try LegadoRuleParser.value(html: "", rule: "@get:{bid}")
    }
    check(stored == "123", "inline put/get")
    let jsonPages = try LegadoRuleParser.values(html: "{}", rule: "@js:['one','two']")
    check(jsonPages == ["one", "two"], "explicit JS before JSON response")
    let oldChapterData = Data(#"{"url":"x","title":"旧章","bookUrl":"b","index":0,"isVip":false,"isPay":false}"#.utf8)
    let oldChapter = try JSONDecoder().decode(BookChapter.self, from: oldChapterData)
    check(oldChapter.variable == nil, "old chapter JSON remains decodable")
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RuleFixtureProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let network = NetworkManager(session: session)
    let engine = BookSourceEngine(network: network)
    var source = BookSource(bookSourceUrl: "https://fixture.test/", bookSourceName: "fixture")
    source.searchUrl = "/search"
    source.ruleSearch = SearchRule(bookList: ".book", name: "a@text", bookUrl: "a@href")
    source.ruleBookInfo = BookInfoRule(name: "h1@text", tocUrl: "a.toc@href")
    source.ruleToc = TocRule(chapterList: "a.chapter", chapterName: "text", chapterUrl: "href", nextTocUrl: "option@value")
    source.ruleContent = ContentRule(content: ".article@html", nextContentUrl: "option@value")
    let results = try await engine.search(keyword: "测试", bookSource: source)
    check(results.first?.bookUrl == "https://fixture.test/mirror/book/info", "search final response base")
    let book = try await engine.getBookInfo(bookUrl: "https://fixture.test/info", bookSource: source)
    check(book.bookUrl == "https://fixture.test/info" && book.tocUrl == "https://fixture.test/mirror/book/toc/", "detail identity and base")
    var tocBook = book
    tocBook.tocUrl = "https://fixture.test/toc"
    let chapters = try await engine.getChapterList(book: tocBook, bookSource: source)
    check(chapters.map(\.title) == ["一", "二", "三"], "multi-page directory dedup")
    let content = try await engine.getChapterContent(chapter: BookChapter(url: "https://fixture.test/content", title: "正文", bookUrl: book.bookUrl, index: 0), bookSource: source)
    check(content == "正文一\n正文二\n正文三", "multi-page content order: \(content)")
    let retry = try await network.fetch(SourceRequest.parse("/retry,{\"retry\":1}", baseURL: "https://fixture.test/"))
    check(retry.text == "ok", "transient retry")
    let task = Task { try await network.get(url: "https://fixture.test/slow") }
    try await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    do { _ = try await task.value; preconditionFailure("cancelled request succeeded") }
    catch is CancellationError { }
    catch let error as URLError { check(error.code == .cancelled, "URLSession cancellation") }
    let ajax = Task {
        try await JavaScriptEngine.withScope(network: network) {
            try JavaScriptEngine.shared.evaluateRule("java.ajax('/slow').body()",
                variables: ["baseUrl": "https://fixture.test/"])
        }
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    ajax.cancel()
    do { _ = try await ajax.value; preconditionFailure("ajax cancellation failed") }
    catch { check(ajax.isCancelled, "ajax cancelled") }
    let jsList = try LegadoRuleParser.values(html: "", rule: "@js:['a','b']")
    check(jsList == ["a", "b"], "JS array pagination")
    let template = try LegadoRuleParser.value(html: json, rule: "{{$.books[0].name}}/{{java.getString('$.books[1].name')}}")
    check(template == "A/B", "JSON and JS template")
    let firstPage = try SourceRequest.parse("https://fixture.test/toc", baseURL: "https://fixture.test/")
    do {
        let _: [String] = try await SourcePagination.collect(first: firstPage, limit: 1, fetch: network.fetch) { response in
            ([response.text], [try SourceRequest.parse("two", baseURL: response.url.absoluteString)])
        }
        preconditionFailure("page cap must report failure")
    } catch SourceRequestError.pageLimit { }
    print("PASS: advanced templates, JSONPath, XPath, JS isolation, request config, pagination, redirect-base, retry and cancellation")
}

private func tryValueList(_ json: String, _ rule: String) -> [String] {
    do { return try LegadoRuleParser.values(html: json, rule: rule) }
    catch { preconditionFailure("\(rule): \(error)") }
}
