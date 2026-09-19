import Foundation
import SwiftSoup
import JavaScriptCore

/// 书源解析引擎
class BookSourceEngine {
    static let shared = BookSourceEngine()
    
    private init() {}
    
    // 搜索书籍
    func search(keyword: String, bookSource: BookSource) async throws -> [SearchBook] {
        try Task.checkCancellation()
        guard let searchUrl = bookSource.searchUrl else {
            throw BookSourceError.noSearchUrl
        }
        
        print("🔍 搜索调试信息:")
        print("  书源: \(bookSource.bookSourceName)")
        print("  baseUrl: \(bookSource.bookSourceUrl)")
        print("  searchUrl原始: \(searchUrl)")
        
        // 解析URL和请求配置（支持逗号分隔的格式）
        // 查找 ",{" 或 ",[" 的组合位置（URL和配置的分隔符）
        var urlPart = searchUrl
        var requestConfig: [String: Any]?
        
        // 从后往前找 ",{" 或 ",["
        if let range = searchUrl.range(of: ",\\s*[\\{\\[]", options: [.regularExpression, .backwards]) {
            let commaIndex = range.lowerBound
            let jsonStartIndex = searchUrl.index(after: commaIndex)
            let potentialJsonPart = String(searchUrl[jsonStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            urlPart = String(searchUrl[..<commaIndex])
            print("  URL部分: \(urlPart)")
            print("  配置部分: \(potentialJsonPart)")
            
            // 尝试解析JSON配置
            if let configData = potentialJsonPart.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] {
                requestConfig = json
                print("  ✅ 解析到请求配置: \(json)")
            }
        }
        
        // 先处理页码表达式
        var url = evaluateSimpleExpressions(in: urlPart, page: 1)
        print("  处理页码后: \(url)")
        
        // 替换body中的关键词（如果有配置）
        if var config = requestConfig {
            if let body = config["body"] as? String {
                let replacedBody = body
                    .replacingOccurrences(of: "{{key}}", with: keyword)
                    .replacingOccurrences(of: "{key}", with: keyword)
                config["body"] = replacedBody
                requestConfig = config
            }
        }
        
        // 替换URL中的关键词
        url = url
            .replacingOccurrences(of: "{{key}}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
            .replacingOccurrences(of: "{key}", with: keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)
        
        print("  替换关键词后URL: \(url)")
        
        // 处理相对URL（补全协议和域名）
        url = resolveUrl(url, baseUrl: bookSource.bookSourceUrl)
        
        print("  最终URL: \(url)")
        
        // 发起网络请求
        let html: String
        
        // 合并headers：优先使用searchUrl中的headers配置
        var finalHeaders = parseHeaders(bookSource.header) ?? [:]
        if let config = requestConfig, let searchHeaders = config["headers"] as? [String: String] {
            for (key, value) in searchHeaders {
                finalHeaders[key] = value
            }
            print("  📋 使用searchUrl中的headers: \(searchHeaders)")
        }
        
        if let config = requestConfig, let method = config["method"] as? String, method.uppercased() == "POST" {
            // 检查是否需要webView
            if let needWebView = config["webView"] as? Bool, needWebView {
                print("⚠️ 该书源需要webView支持，将尝试不使用webView直接请求（可能失败）")
            }
            
            // POST请求
            let body = config["body"] as? String ?? ""
            print("  📤 使用POST请求")
            print("  📤 URL: \(url)")
            print("  📤 Body: \(body)")
            let bodyData = body.data(using: .utf8)
            print("  📤 Body Data字节数: \(bodyData?.count ?? 0)")
            html = try await NetworkManager.shared.post(url: url, body: bodyData, headers: finalHeaders)
            print("  📥 收到响应，长度: \(html.count) 字符")
            if html.count < 200 {
                print("  📥 完整响应: \(html)")
            } else {
                print("  📥 响应前200字符: \(String(html.prefix(200)))")
            }
        } else {
            // GET请求
            print("  🌐 发起GET请求...")
            print("  📋 实际发送的headers: \(finalHeaders)")
            print("  📋 headers数量: \(finalHeaders.count)")
            for (key, value) in finalHeaders {
                print("     \(key): \(value)")
            }
            do {
                html = try await NetworkManager.shared.get(url: url, headers: finalHeaders)
                print("  ✅ GET请求成功，收到响应长度: \(html.count) 字符")
                if html.count < 500 {
                    print("  📄 完整响应: \(html)")
                } else {
                    print("  📄 响应前500字符: \(String(html.prefix(500)))")
                }
            } catch {
                if !Task.isCancelled {
                    print("  ❌ GET请求失败，错误详情:")
                    print("     错误类型: \(type(of: error))")
                    print("     错误描述: \(error.localizedDescription)")
                    if let urlError = error as? URLError {
                        print("     URLError代码: \(urlError.code.rawValue)")
                        print("     URLError原始值: \(urlError.code)")
                        print("     失败URL: \(urlError.failureURLString ?? "未知")")
                    }
                }
                throw error
            }
        }
        
        // 解析搜索结果
        try Task.checkCancellation()
        do {
            return try parseSearchResult(html: html, rule: bookSource.ruleSearch, baseUrl: bookSource.bookSourceUrl, bookSource: bookSource, keyword: keyword)
        } catch {
            print("❌ 解析搜索结果失败: \(error)")
            print("   HTML前500字符: \(String(html.prefix(500)))")
            throw error
        }
    }

    /// 将搜索结果中的可靠字段补回详情解析结果，避免书源详情页规则失效时保存空书籍。
    func mergeSearchResult(_ result: SearchBook, into book: inout Book, bookSource: BookSource) {
        if book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            book.name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if book.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            book.author = result.author.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if book.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            book.bookUrl = result.bookUrl
        }
        if book.tocUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            book.tocUrl = result.bookUrl
        }
        if book.coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            book.coverUrl = result.coverUrl
        }
        if book.intro?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            book.intro = result.intro
        }
        if book.kind?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            book.kind = result.kind
        }
        if book.latestChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            book.latestChapterTitle = result.latestChapterTitle
        }
        if book.wordCount?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            book.wordCount = result.wordCount
        }

        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
    }

    /// 获取书源的发现页内容。
    func explore(bookSource: BookSource, screen: String? = nil) async throws -> [SearchBook] {
        guard let exploreUrl = bookSource.exploreUrl,
              let exploreRule = bookSource.ruleExplore,
              let listRule = exploreRule.bookList,
              !listRule.isEmpty else {
            throw BookSourceError.noRule
        }

        let url = resolveUrl(evaluateSimpleExpressions(in: exploreUrl, page: 1), baseUrl: bookSource.bookSourceUrl)
        let html = try await NetworkManager.shared.get(url: url, headers: parseHeaders(bookSource.header))
        let rule = SearchRule(
            bookList: listRule,
            name: exploreRule.name,
            author: exploreRule.author,
            kind: exploreRule.kind,
            intro: exploreRule.intro,
            coverUrl: exploreRule.coverUrl,
            bookUrl: exploreRule.bookUrl,
            wordCount: exploreRule.wordCount,
            lastChapter: exploreRule.lastChapter
        )
        return try parseSearchResult(
            html: html,
            rule: rule,
            baseUrl: url,
            bookSource: bookSource,
            keyword: screen ?? ""
        )
    }
    
    // 获取书籍信息
    func getBookInfo(bookUrl: String, bookSource: BookSource) async throws -> Book {
        let html = try await NetworkManager.shared.get(url: bookUrl, headers: parseHeaders(bookSource.header))
        
        return try parseBookInfo(html: html, bookUrl: bookUrl, rule: bookSource.ruleBookInfo, bookSource: bookSource)
    }
    
    // 获取章节列表
    func getChapterList(book: Book, bookSource: BookSource) async throws -> [BookChapter] {
        guard let tocRule = bookSource.ruleToc else { throw BookSourceError.noRule }
        var currentURL = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        var visited: Set<String> = []
        var chapters: [BookChapter] = []

        for _ in 0..<50 {
            guard !visited.contains(currentURL) else { break }
            visited.insert(currentURL)
            let html = try await NetworkManager.shared.get(url: currentURL, headers: parseHeaders(bookSource.header))
            let page = try parseChapterList(
                html: html,
                bookUrl: book.bookUrl,
                baseURL: currentURL,
                rule: tocRule,
                jsLib: bookSource.jsLib
            )
            chapters.append(contentsOf: page)

            guard let nextRule = tocRule.nextTocUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !nextRule.isEmpty else { break }
            let next = try parseNextURL(html: html, rule: nextRule, baseURL: currentURL, jsLib: bookSource.jsLib)
            guard !next.isEmpty else { break }
            currentURL = next
        }

        for index in chapters.indices { chapters[index].index = index }
        return chapters
    }
    
    // 获取章节内容
    func getChapterContent(chapter: BookChapter, bookSource: BookSource) async throws -> String {
        print("📖 准备获取章节内容")
        print("📖 chapter.url: \(chapter.url)")
        print("📖 chapter.bookUrl: \(chapter.bookUrl)")

        // 从bookUrl中提取bookid（bookUrl是正确的）
        var actualBookid: String?
        if let urlComponents = URLComponents(string: chapter.bookUrl),
           let queryItems = urlComponents.queryItems,
           let bookidItem = queryItems.first(where: { $0.name == "bookid" }),
           let bookid = bookidItem.value, bookid != "undefined" {
            actualBookid = bookid
            print("📦 从bookUrl提取bookid: \(bookid)")
            // 保存到JS缓存
            _ = try? JavaScriptEngine.shared.evaluate("java.put('bookid', '\(bookid)');", variables: [:])
        }

        // 检查chapter.url是否包含undefined，如果是则重新构建URL
        var finalUrl = chapter.url
        if finalUrl.contains("bookid=undefined"), let bookid = actualBookid {
            // 从chapter.url提取itemid
            if let urlComponents = URLComponents(string: chapter.url),
               let queryItems = urlComponents.queryItems,
               let itemidItem = queryItems.first(where: { $0.name == "itemid" }),
               let itemid = itemidItem.value {
                // 重新构建正确的URL
                var components = urlComponents
                components.queryItems = [
                    URLQueryItem(name: "bookid", value: bookid),
                    URLQueryItem(name: "itemid", value: itemid)
                ]
                if let newUrl = components.url?.absoluteString {
                    finalUrl = newUrl
                    print("✅ 重新构建章节URL: \(finalUrl)")
                }
            }
        }

        // 修正章节URL，处理重复路径问题（如 /bqg/1099590//bqg/1099590/xxx.html）
        if finalUrl.hasPrefix("http") {
            // 检测并修复重复路径：提取协议后的部分，查找双斜杠后的重复路径
            if let range = finalUrl.range(of: "://") {
                let afterProtocol = String(finalUrl[range.upperBound...])
                // 如果存在双斜杠（非协议部分）
                if let doubleSlashIndex = afterProtocol.firstIndex(of: "/"),
                   afterProtocol[doubleSlashIndex...].contains("//") {
                    // 分割成域名和路径
                    let components = afterProtocol.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    if components.count == 2 {
                        let domain = components[0]
                        var path = String(components[1])
                        
                        // 清理路径中的连续双斜杠，并检测重复路径段
                        // 例如 /bqg/1099590//bqg/1099590/xxx.html -> /bqg/1099590/xxx.html
                        if path.contains("//") {
                            let pathSegments = path.split(separator: "/", omittingEmptySubsequences: true)
                            var cleanedSegments: [String] = []
                            var i = 0
                            while i < pathSegments.count {
                                let segment = String(pathSegments[i])
                                cleanedSegments.append(segment)
                                
                                // 检查是否有连续重复的路径段
                                if i + 1 < pathSegments.count && 
                                   cleanedSegments.count >= 2 &&
                                   pathSegments[i + 1] == pathSegments[i - cleanedSegments.count + 1] {
                                    // 发现重复模式，跳过后续的重复段
                                    let repeatCount = cleanedSegments.count - 1
                                    var skip = 0
                                    for j in 0..<repeatCount {
                                        if i + 1 + j < pathSegments.count && 
                                           pathSegments[i + 1 + j] == pathSegments[i - repeatCount + 1 + j] {
                                            skip += 1
                                        } else {
                                            break
                                        }
                                    }
                                    if skip > 0 {
                                        i += skip
                                    }
                                }
                                i += 1
                            }
                            path = cleanedSegments.joined(separator: "/")
                            let urlProtocol = String(finalUrl[..<range.upperBound])
                            finalUrl = "\(urlProtocol)\(domain)/\(path)"
                            print("✅ 修复重复路径: \(finalUrl)")
                        }
                    }
                }
            }
        } else {
            // 相对路径，使用resolveUrl拼接
            if let base = URL(string: chapter.bookUrl), let url = URL(string: finalUrl, relativeTo: base) {
                finalUrl = url.absoluteURL.absoluteString
                print("✅ 章节URL已规范拼接: \(finalUrl)")
            } else {
                finalUrl = chapter.bookUrl + finalUrl
                print("⚠️ 章节URL兜底拼接: \(finalUrl)")
            }
        }

        guard let contentRule = bookSource.ruleContent else {
            throw BookSourceError.noRule
        }

        var currentURL = finalUrl
        var visited: Set<String> = []
        var pages: [String] = []
        for _ in 0..<30 {
            guard !visited.contains(currentURL) else { break }
            visited.insert(currentURL)
            let html = try await NetworkManager.shared.get(url: currentURL, headers: parseHeaders(bookSource.header))
            pages.append(try parseContent(html: html, rule: contentRule, jsLib: bookSource.jsLib))
            guard let nextRule = contentRule.nextContentUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !nextRule.isEmpty else { break }
            let nextURL = try parseNextURL(
                html: html,
                rule: nextRule,
                baseURL: currentURL,
                jsLib: bookSource.jsLib
            )
            guard !nextURL.isEmpty else { break }
            currentURL = nextURL
        }
        return pages.joined(separator: "\n")
    }

    /// 供 RSS 订阅源和发现页复用的统一规则入口。
    func parseRuleValue(html: String, rule: String, baseUrl: String, jsLib: String? = nil) throws -> String {
        try LegadoRuleParser.value(html: html, rule: rule, baseURL: baseUrl, jsLib: jsLib)
    }

    func parseRuleValues(html: String, rule: String, baseUrl: String, jsLib: String? = nil) throws -> [String] {
        try LegadoRuleParser.values(html: html, rule: rule, baseURL: baseUrl, jsLib: jsLib)
    }

    func selectRuleElements(html: String, rule: String, baseUrl: String) throws -> [Element] {
        try LegadoRuleParser.selectElements(html: html, rule: rule, baseURL: baseUrl)
    }

    private func parseNextURL(html: String, rule: String, baseURL: String, jsLib: String?) throws -> String {
        let value: String
        if containsJavaScript(rule) {
            value = try JavaScriptEngine.shared.parseJSRule(
                rule,
                html: html,
                baseUrl: baseURL,
                jsLib: jsLib
            )
        } else if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
                    html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            value = (try? LegadoRuleParser.jsonValue(from: html, rule: rule)) ?? ""
        } else {
            value = (try? LegadoRuleParser.value(html: html, rule: rule, baseURL: baseURL, jsLib: jsLib)) ?? ""
        }
        return resolveUrl(value, baseUrl: baseURL)
    }
    
    // MARK: - 解析方法
    
    // 解析搜索结果
    private func parseSearchResult(html: String, rule: SearchRule?, baseUrl: String, bookSource: BookSource, keyword: String) throws -> [SearchBook] {
        guard let rule = rule else {
            throw BookSourceError.noRule
        }
        
        var books: [SearchBook] = []
        
        // 获取书籍列表 - 支持JS规则
        guard let bookListRule = rule.bookList else {
            throw BookSourceError.noRule
        }

        if RegexAllInOneParser.isAllInOneRule(bookListRule) {
            return try parseSearchResultWithAllInOne(
                html: html,
                rule: rule,
                baseUrl: baseUrl,
                bookSource: bookSource
            )
        }
        
        // 检查是否是JS规则
        if containsJavaScript(bookListRule) {
            // 使用JavaScript解析
            return try parseSearchResultWithJS(html: html, rule: rule, baseUrl: baseUrl, bookSource: bookSource, keyword: keyword)
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            // 使用JSON解析
            return try parseSearchResultWithJSON(json: html, rule: rule, baseUrl: baseUrl, bookSource: bookSource)
        }
        
        // 使用CSS选择器解析
        print("  📝 开始解析HTML，bookList规则: \(bookListRule)")
        let doc = try SwiftSoup.parse(html)
        print("  📝 HTML解析成功")

        // 处理bookList规则中的@符号语法
        var elements: Elements
        if bookListRule.contains("@") {
            // 分离选择器和子选择器
            let parts = bookListRule.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                var parentSelector = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var childSelector = String(parts[1]).trimmingCharacters(in: .whitespaces)

                // 转换Android阅读选择器语法
                parentSelector = convertToStandardCSSSelector(parentSelector)
                childSelector = convertToStandardCSSSelector(childSelector)

                // 先选择父元素
                let parentElements = try doc.select(parentSelector)
                print("  📝 找到 \(parentElements.count) 个父元素（\(parentSelector)）")

                // 从每个父元素中选择子元素
                elements = Elements()
                for parent in parentElements {
                    let children = try parent.select(childSelector)
                    for child in children {
                        elements.add(child)
                    }
                }
                print("  📝 从父元素中找到 \(elements.count) 个子元素（\(childSelector)）")
            } else {
                // 转换选择器语法后直接选择
                let convertedSelector = convertToStandardCSSSelector(bookListRule)
                elements = try doc.select(convertedSelector)
                print("  📝 找到 \(elements.count) 个书籍元素")
            }
        } else {
            // 转换选择器语法后直接选择
            let convertedSelector = convertToStandardCSSSelector(bookListRule)
            elements = try doc.select(convertedSelector)
            print("  📝 找到 \(elements.count) 个书籍元素")
        }
        
        for element in elements {
            var book = SearchBook()
            
            do {
                // 解析书名
                if let nameRule = rule.name {
                    book.name = try parseRuleValue(element: element, rule: nameRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                }
                
                // 解析作者
                if let authorRule = rule.author {
                    book.author = try parseRuleValue(element: element, rule: authorRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                }
                
                // 解析书籍URL
                if let bookUrlRule = rule.bookUrl {
                    var bookUrl = try parseRuleValue(element: element, rule: bookUrlRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                    if !bookUrl.starts(with: "http") {
                        bookUrl = resolveUrl(bookUrl, baseUrl: baseUrl)
                    }
                    book.bookUrl = bookUrl
                }
                
                // 解析封面
                if let coverRule = rule.coverUrl {
                    var coverUrl = try parseRuleValue(element: element, rule: coverRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                    if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                        coverUrl = resolveUrl(coverUrl, baseUrl: baseUrl)
                    }
                    book.coverUrl = coverUrl
                }
                
                // 解析简介
                if let introRule = rule.intro, !introRule.isEmpty {
                    book.intro = try parseRuleValue(element: element, rule: introRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                }
                
                // 解析分类
                if let kindRule = rule.kind {
                    book.kind = try parseRuleValue(element: element, rule: kindRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                }
                
                // 解析最新章节
                if let lastChapterRule = rule.lastChapter {
                    book.latestChapterTitle = try parseRuleValue(element: element, rule: lastChapterRule, html: html, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                }
                
                // 保存书源信息
                book.bookSourceUrl = bookSource.bookSourceUrl
                book.bookSourceName = bookSource.bookSourceName
                
                // 只添加有效的书籍（至少有书名和URL）
                if !book.name.isEmpty && !book.bookUrl.isEmpty {
                    books.append(book)
                }
            } catch {
                print("⚠️ 解析单个书籍元素失败: \(error)")
                print("   元素HTML: \(String((try? element.outerHtml())?.prefix(200) ?? ""))")
                // 继续解析下一个元素
                continue
            }
        }
        
        return books
    }

    private func parseSearchResultWithAllInOne(
        html: String,
        rule: SearchRule,
        baseUrl: String,
        bookSource: BookSource
    ) throws -> [SearchBook] {
        guard let listRule = rule.bookList else { throw BookSourceError.noRule }
        let matches = try RegexAllInOneParser.parse(rule: listRule, content: html)

        return matches.compactMap { match in
            var book = SearchBook()
            let read: (String?) -> String = { rule in
                guard let rule else { return "" }
                if let direct = match[rule.trimmingCharacters(in: .whitespacesAndNewlines)] {
                    return direct
                }
                let pattern = #"\$(\d+)"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return rule }
                var value = rule
                let source = rule as NSString
                for item in regex.matches(in: rule, range: NSRange(location: 0, length: source.length)).reversed() {
                    let key = "$\(source.substring(with: item.range(at: 1)))"
                    value = (value as NSString).replacingCharacters(in: item.range, with: match[key] ?? "")
                }
                return value
            }
            book.name = read(rule.name)
            book.author = read(rule.author)
            book.bookUrl = resolveUrl(read(rule.bookUrl), baseUrl: baseUrl)
            book.coverUrl = resolveUrl(read(rule.coverUrl), baseUrl: baseUrl)
            book.intro = read(rule.intro)
            book.kind = read(rule.kind)
            book.latestChapterTitle = read(rule.lastChapter)
            book.wordCount = read(rule.wordCount)
            book.bookSourceUrl = bookSource.bookSourceUrl
            book.bookSourceName = bookSource.bookSourceName
            return book.name.isEmpty || book.bookUrl.isEmpty ? nil : book
        }
    }
    
    // 使用统一的 Legado 规则 evaluator；旧实现保留为兼容性 fallback。
    private func parseRuleValue(element: Element, rule: String, html: String, baseUrl: String, jsLib: String? = nil) throws -> String {
        do {
            return try LegadoRuleParser.value(in: element, rule: rule, baseURL: baseUrl, jsLib: jsLib)
        } catch {
            return try legacyParseRuleValue(element: element, rule: rule, html: html, baseUrl: baseUrl)
        }
    }

    // 旧版 macOS 规则解析器，作为异常规则的 fallback。
    private func legacyParseRuleValue(element: Element, rule: String, html: String, baseUrl: String) throws -> String {
        // 使用RuleAnalyzer拆分规则
        let segments = RuleAnalyzer.splitRule(rule)
        
        var result: String = try element.outerHtml()
        
        // 按顺序执行每个规则片段
        for segment in segments {
            let cleanRule = RuleAnalyzer.cleanRulePrefix(segment.content, mode: segment.mode)
            
            switch segment.mode {
            case .js:
                // JavaScript规则
                result = try JavaScriptEngine.shared.parseJSRule("@js:\(cleanRule)", html: result, baseUrl: baseUrl)
                
            case .json:
                // JSON 规则由 LegadoRuleParser 优先处理；仅在旧 fallback 中保留原值。
                print("⚠️ JSON规则进入旧 fallback: \(cleanRule)")
                return ""
                
            case .xpath:
                // XPath 规则由 LegacyRuleEvaluator 优先处理；仅在旧 fallback 中保留原值。
                print("⚠️ XPath规则进入旧 fallback: \(cleanRule)")
                return ""
                
            case .regex:
                // 正则表达式规则（简化实现）
                if let regex = try? NSRegularExpression(pattern: cleanRule, options: []) {
                    let nsResult = result as NSString
                    let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
                    if let firstMatch = matches.first, firstMatch.numberOfRanges > 1 {
                        result = nsResult.substring(with: firstMatch.range(at: 1))
                    }
                }
                
            case .default:
                // CSS选择器解析
                // 支持属性选择：@attr, @src, @href等
                // 也支持子选择器：@p, @a 等（相当于空格）
                if cleanRule.contains("@") {
                    let parts = cleanRule.split(separator: "@", maxSplits: 1)
                    if parts.count == 2 {
                        var selector = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let attr = String(parts[1]).trimmingCharacters(in: .whitespaces)

                        // 转换Android阅读的选择器语法为标准CSS选择器
                        selector = convertToStandardCSSSelector(selector)

                        // 处理索引语法：.author.0 -> (.author, 0), a.1 -> (a, 1), a.-1 -> (a, -1)
                        var index: Int? = nil
                        if let lastDotIndex = selector.lastIndex(of: "."),
                           lastDotIndex != selector.startIndex {
                            let afterDot = selector[selector.index(after: lastDotIndex)...]
                            if let idx = Int(afterDot) {
                                index = idx
                                selector = String(selector[..<lastDotIndex])
                            }
                        }
                        
                        let doc = try SwiftSoup.parse(result)
                        
                        // 检查@后面是特殊属性（text/html）、HTML标签（子选择器）还是普通属性
                        let specialAttrs = ["text", "html"]
                        let htmlTags = ["p", "a", "div", "span", "li", "td", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "img", "ul", "ol", "dl", "dt", "dd"]
                        let isSpecialAttr = specialAttrs.contains(attr.lowercased())
                        let isSubSelector = htmlTags.contains(attr.lowercased())
                        
                        if isSpecialAttr {
                            // @text, @html 特殊处理
                            var targetElement: Element? = nil
                            if !selector.isEmpty {
                                let elements = try doc.select(selector)
                                if let idx = index {
                                    if idx >= 0 && idx < elements.count {
                                        targetElement = elements[idx]
                                    } else if idx < 0 && -idx <= elements.count {
                                        targetElement = elements[elements.count + idx]
                                    }
                                } else {
                                    targetElement = elements.first()
                                }
                            } else {
                                targetElement = try? doc.select("body").first()
                            }
                            
                            if let element = targetElement {
                                if attr.lowercased() == "text" {
                                    result = try element.text()
                                } else if attr.lowercased() == "html" {
                                    result = try element.html()
                                }
                            } else {
                                result = ""
                            }
                        } else if isSubSelector {
                            // @p, @a 等作为子选择器
                            // 先根据selector+index选择父元素
                            var parentElement: Element? = nil
                            if !selector.isEmpty {
                                let parentElements = try doc.select(selector)
                                if let idx = index {
                                    if idx >= 0 && idx < parentElements.count {
                                        parentElement = parentElements[idx]
                                    } else if idx < 0 && -idx <= parentElements.count {
                                        parentElement = parentElements[parentElements.count + idx]
                                    }
                                } else {
                                    parentElement = parentElements.first()
                                }
                            } else {
                                parentElement = try? doc.select("body").first()
                            }
                            
                            // 从父元素中选择子元素，返回所有匹配的HTML
                            if let parent = parentElement {
                                let childElements = try parent.select(attr)
                                result = try childElements.map { try $0.outerHtml() }.joined()
                            } else {
                                result = ""
                            }
                        } else {
                            // 作为属性选择器
                            if selector.isEmpty {
                                // 直接从当前元素获取属性
                                if let root = try? doc.select("body").first() {
                                    result = try root.attr(attr)
                                }
                            } else {
                                // 从子元素获取属性
                                let elements = try doc.select(selector)
                                var selected: Element? = nil
                                if let idx = index {
                                    if idx >= 0 && idx < elements.count {
                                        selected = elements[idx]
                                    } else if idx < 0 && -idx <= elements.count {
                                        selected = elements[elements.count + idx]
                                    }
                                } else {
                                    selected = elements.first()
                                }
                                
                                if let selected = selected {
                                    if attr == "text" {
                                        result = try selected.text()
                                    } else if attr == "html" {
                                        result = try selected.html()
                                    } else {
                                        // 获取属性值 - 优先使用abs:前缀获取绝对URL
                                        if attr == "href" || attr == "src" {
                                            // 先尝试获取原始属性值（相对路径）
                                            result = try selected.attr(attr)
                                            print("🔍 [parseRuleValue] 获取\(attr)属性: \(result)")
                                        } else {
                                            result = try selected.attr(attr)
                                        }
                                    }
                                } else {
                                    result = ""
                                }
                            }
                        }
                    }
                } else {
                    // 普通文本选择
                    // 处理索引语法
                    var selector = cleanRule
                    var index: Int? = nil
                    if let lastDotIndex = selector.lastIndex(of: "."),
                       lastDotIndex != selector.startIndex {
                        let afterDot = selector[selector.index(after: lastDotIndex)...]
                        if let idx = Int(afterDot) {
                            index = idx
                            selector = String(selector[..<lastDotIndex])
                        }
                    }
                    
                    let doc = try SwiftSoup.parse(result)
                    let elements = try doc.select(selector)
                    var selected: Element? = nil
                    if let idx = index {
                        if idx >= 0 && idx < elements.count {
                            selected = elements[idx]
                        } else if idx < 0 && -idx <= elements.count {
                            selected = elements[elements.count + idx]
                        }
                    } else {
                        selected = elements.first()
                    }
                    
                    if let selected = selected {
                        result = try selected.text()
                    }
                }
            }
        }
        
        return result
    }
    
    // 使用JSON解析搜索结果
    private func parseSearchResultWithJSON(json: String, rule: SearchRule, baseUrl: String, bookSource: BookSource) throws -> [SearchBook] {
        print("📦 使用JSON解析")
        
        guard json.data(using: .utf8) != nil else {
            throw BookSourceError.parseError
        }
        
        var books: [SearchBook] = []
        
        // 获取书籍数组
        guard let bookListRule = rule.bookList else {
            throw BookSourceError.noRule
        }
        
        // bookList 规则可能是 "data.list"、"$.data.list" 或带数组切片。
        guard let bookArray = try? LegadoRuleParser.jsonObjects(from: json, rule: bookListRule),
              !bookArray.isEmpty else {
            print("❌ 无法从JSON中获取书籍数组: \(bookListRule)")
            return books
        }
        
        print("✅ 找到 \(bookArray.count) 本书")
        
        // 解析每本书
        for bookData in bookArray {
            var book = SearchBook()
            
            // 解析书名
            if let nameRule = rule.name {
                book.name = extractJSONValue(from: bookData, rule: nameRule)
            }
            
            // 解析作者
            if let authorRule = rule.author {
                book.author = extractJSONValue(from: bookData, rule: authorRule)
            }
            
            // 解析书籍URL
            if let bookUrlRule = rule.bookUrl {
                var bookUrl = bookUrlRule
                // 先处理模板变量 {{$.bookid}}
                bookUrl = replaceTemplates(in: bookUrl, with: bookData)
                // 如果没有模板，尝试作为字段名提取
                if bookUrl == bookUrlRule && !bookUrl.contains("{{") {
                    bookUrl = extractJSONValue(from: bookData, rule: bookUrlRule)
                }
                // 处理相对URL
                bookUrl = resolveUrl(bookUrl, baseUrl: baseUrl)
                book.bookUrl = bookUrl
            }
            
            // 解析封面
            if let coverRule = rule.coverUrl {
                var coverUrl = extractJSONValue(from: bookData, rule: coverRule)
                coverUrl = resolveUrl(coverUrl, baseUrl: baseUrl)
                book.coverUrl = coverUrl
            }
            
            // 解析简介
            if let introRule = rule.intro {
                book.intro = extractJSONValue(from: bookData, rule: introRule)
            }
            
            // 解析分类
            if let kindRule = rule.kind {
                var kind = kindRule
                // 处理模板: {{$.category}},{{$.status}}
                kind = replaceTemplates(in: kind, with: bookData)
                book.kind = kind
            }
            
            // 解析最新章节
            if let lastChapterRule = rule.lastChapter {
                book.latestChapterTitle = extractJSONValue(from: bookData, rule: lastChapterRule)
            }
            
            // 解析字数
            if let wordCountRule = rule.wordCount {
                book.wordCount = extractJSONValue(from: bookData, rule: wordCountRule)
            }
            
            // 保存书源URL
            book.bookSourceUrl = bookSource.bookSourceUrl
            book.bookSourceName = bookSource.bookSourceName
            
            books.append(book)
        }
        
        return books
    }
    
    // 从JSON对象中提取值
    private func extractJSONValue(from jsonObject: [String: Any], rule: String) -> String {
        if rule.contains("{{") {
            return replaceTemplates(in: rule, with: jsonObject)
        }
        return (try? LegadoRuleParser.jsonValue(from: jsonObject, rule: rule)) ?? ""
    }
    
    // 替换 Android Legado 常见模板：{{$.field}}、{{field}} 和 {$._id}。
    private func replaceTemplates(in text: String, with jsonObject: [String: Any]) -> String {
        var result = text

        let pattern = "\\{\\{([^}]+)\\}\\}|\\{(\\$[^}]+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        // 从后向前替换
        for match in matches.reversed() {
            if match.numberOfRanges >= 3 {
                let fullRange = match.range(at: 0)
                let fieldRange = match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range(at: 2)
                var fieldName = nsString.substring(with: fieldRange)
                if let separator = fieldName.firstIndex(of: ";") {
                    fieldName = String(fieldName[..<separator])
                }
                fieldName = fieldName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = try? LegadoRuleParser.jsonValue(from: jsonObject, rule: fieldName) {
                    result = (result as NSString).replacingCharacters(in: fullRange, with: value)
                }
            }
        }
        
        return result
    }
    
    // 使用JavaScript解析搜索结果
    private func parseSearchResultWithJS(html: String, rule: SearchRule, baseUrl: String, bookSource: BookSource, keyword: String) throws -> [SearchBook] {
        guard let bookListRule = rule.bookList else {
            throw BookSourceError.noRule
        }
        
        print("🔍 使用JS解析bookList规则: \(bookListRule.prefix(100))")
        
        var books: [SearchBook] = []
        
        // 执行bookList JS规则获取书籍列表
        let jsEngine = JavaScriptEngine.shared
        
        do {
            // 使用RuleAnalyzer提取所有片段
            let segments = RuleAnalyzer.splitRule(bookListRule)
            
            print("🔍 规则分段数量: \(segments.count)")
            for (index, segment) in segments.enumerated() {
                print("  片段\(index): 模式=\(segment.mode), 内容前50字符=\(segment.content.prefix(50))")
            }
            
            // 先处理非JS片段（如JSONPath）
            var currentResult: Any = html
            
            for segment in segments {
                if segment.mode == .json || segment.mode == .default {
                    // 处理JSONPath规则
                    let jsonPathRule = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !jsonPathRule.isEmpty && jsonPathRule.hasPrefix("$") {
                        print("🔍 执行JSONPath规则: \(jsonPathRule)")
                        
                        // 确保输入是JSON字符串
                        if let jsonString = currentResult as? String {
                            // 使用JSONPath提取（简化版：只处理$.items[:10]这种格式）
                            if let jsonData = jsonString.data(using: .utf8),
                               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                                
                                // 解析JSONPath
                                var extracted: Any = jsonObject
                                
                                if jsonPathRule.hasPrefix("$.") {
                                    let path = jsonPathRule.dropFirst(2) // 移除"$."
                                    let components = path.components(separatedBy: ".")
                                    
                                    for component in components {
                                        // 处理数组切片 items[:10]
                                        if component.contains("[") && component.contains("]") {
                                            let parts = component.split(separator: "[")
                                            let key = String(parts[0])
                                            
                                            // 提取数组
                                            if let dict = extracted as? [String: Any],
                                               let array = dict[key] as? [[String: Any]] {
                                                
                                                // 处理切片 [:10]
                                                let slicePart = parts[1].dropLast() // 移除"]"
                                                if slicePart.hasPrefix(":") {
                                                    let countStr = slicePart.dropFirst()
                                                    if let count = Int(countStr) {
                                                        extracted = Array(array.prefix(count))
                                                        print("✅ JSONPath切片成功，提取前\(count)个元素")
                                                    } else {
                                                        extracted = array
                                                    }
                                                } else {
                                                    extracted = array
                                                }
                                            }
                                        } else {
                                            // 普通属性访问
                                            if let dict = extracted as? [String: Any] {
                                                extracted = dict[component] ?? extracted
                                            }
                                        }
                                    }
                                }
                                
                                currentResult = extracted
                                print("✅ JSONPath提取成功，结果类型: \(type(of: extracted))")
                                if let array = extracted as? [[String: Any]] {
                                    print("✅ 提取到数组，包含 \(array.count) 个元素")
                                }
                            }
                        }
                    }
                }
            }
            
            // 找到第一个JS片段
            guard let jsSegment = segments.first(where: { $0.mode == .js }) else {
                throw BookSourceError.noRule
            }
            
            let cleanRule = jsSegment.content
            print("🔍 清理后的规则: \(cleanRule.prefix(200))...")
            
            // 将处理后的result传给JS
            let bookListResult = try jsEngine.evaluate(
                cleanRule,
                variables: ["result": currentResult, "baseUrl": baseUrl, "html": html, "page": 1, "key": keyword],
                jsLib: bookSource.jsLib
            )
            
            print("✅ JS执行成功，结果类型: 数组=\(bookListResult.isArray), 对象=\(bookListResult.isObject), 字符串=\(bookListResult.isString)")
            
            // 处理返回值
            var actualResult = bookListResult
            
            // 如果返回的是字符串（可能是JSON字符串），尝试解析
            if bookListResult.isString, let jsonString = bookListResult.toString() {
                print("🔍 返回的是字符串，长度: \(jsonString.count)")
                print("🔍 字符串内容前100字符: \(jsonString.prefix(100))")
                
                // 尝试解析JSON字符串
                if let jsonData = jsonString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                    // 将解析后的对象重新注入JSContext
                    let tempContext = JSContext()!
                    if let jsonArray = jsonObject as? [[String: Any]] {
                        print("✅ 成功解析为数组，包含 \(jsonArray.count) 个元素")
                        actualResult = JSValue(object: jsonArray, in: tempContext)
                    } else {
                        print("⚠️ JSON解析结果不是数组: \(type(of: jsonObject))")
                    }
                }
            }
            
            // 检查返回类型
            if actualResult.isArray {
                // 如果是数组，遍历每个元素
                let length = actualResult.forProperty("length").toInt32()
                print("📚 找到 \(length) 个结果")
                
                for i in 0..<length {
                    guard let bookItem = actualResult.atIndex(Int(i)) else { continue }
                    
                    var book = SearchBook()
                    
                    // 解析书名
                    if let nameRule = rule.name {
                        do {
                            book.name = try parseJSField(bookItem, rule: nameRule, baseUrl: baseUrl, bookSource: bookSource)
                            print("✅ 解析书名: \(book.name)")
                        } catch {
                            print("❌ 解析书名失败: \(error)")
                        }
                    }
                    
                    // 解析作者
                    if let authorRule = rule.author {
                        do {
                            book.author = try parseJSField(bookItem, rule: authorRule, baseUrl: baseUrl, bookSource: bookSource)
                            print("✅ 解析作者: \(book.author)")
                        } catch {
                            print("❌ 解析作者失败: \(error)")
                        }
                    }
                    
                    // 解析书籍URL
                    if let bookUrlRule = rule.bookUrl {
                        do {
                            var bookUrl = try parseJSField(bookItem, rule: bookUrlRule, baseUrl: baseUrl, bookSource: bookSource)
                            if !bookUrl.starts(with: "http") && !bookUrl.isEmpty {
                                bookUrl = resolveUrl(bookUrl, baseUrl: baseUrl)
                            }
                            book.bookUrl = bookUrl
                            print("✅ 解析URL: \(bookUrl.prefix(50))...")
                        } catch {
                            print("❌ 解析URL失败: \(error)")
                        }
                    }
                    
                    // 解析封面
                    if let coverRule = rule.coverUrl {
                        do {
                            var coverUrl = try parseJSField(bookItem, rule: coverRule, baseUrl: baseUrl, bookSource: bookSource)
                            if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                                coverUrl = resolveUrl(coverUrl, baseUrl: baseUrl)
                            }
                            book.coverUrl = coverUrl
                            print("✅ 解析封面: \(coverUrl.prefix(50))...")
                        } catch {
                            print("❌ 解析封面失败: \(error)")
                        }
                    }
                    
                    // 解析简介
                    if let introRule = rule.intro {
                        do {
                            book.intro = try parseJSField(bookItem, rule: introRule, baseUrl: baseUrl, bookSource: bookSource)
                            print("✅ 解析简介: \(book.intro?.prefix(30) ?? "无")...")
                        } catch {
                            print("❌ 解析简介失败: \(error)")
                        }
                    }
                    
                    // 解析分类
                    if let kindRule = rule.kind {
                        do {
                            book.kind = try parseJSField(bookItem, rule: kindRule, baseUrl: baseUrl, bookSource: bookSource)
                            print("✅ 解析分类: \(book.kind ?? "无")")
                        } catch {
                            print("❌ 解析分类失败: \(error)")
                        }
                    }
                    
                    // 解析最新章节
                    if let lastChapterRule = rule.lastChapter {
                        do {
                            book.latestChapterTitle = try parseJSField(bookItem, rule: lastChapterRule, baseUrl: baseUrl, bookSource: bookSource)
                            print("✅ 解析最新章节: \(book.latestChapterTitle ?? "无")")
                        } catch {
                            print("❌ 解析最新章节失败: \(error)")
                        }
                    }

                    book.bookSourceUrl = bookSource.bookSourceUrl
                    book.bookSourceName = bookSource.bookSourceName
                    
                    if !book.name.isEmpty && !book.bookUrl.isEmpty {
                        books.append(book)
                    }
                }
            } else {
                // 如果不是数组，可能是CSS选择器结果，尝试用原HTML解析
                print("⚠️ bookList返回的不是数组，尝试CSS解析")
                let doc = try SwiftSoup.parse(html)
                if let elements = try? doc.select(bookListRule) {
                    for element in elements {
                        var book = SearchBook()
                        
                        let elementHtml = try element.outerHtml()
                        
                        // 解析各字段
                        if let nameRule = rule.name {
                            book.name = try parseRuleValue(element: element, rule: nameRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                        }
                        
                        if let authorRule = rule.author {
                            book.author = try parseRuleValue(element: element, rule: authorRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                        }
                        
                        if let bookUrlRule = rule.bookUrl {
                            var bookUrl = try parseRuleValue(element: element, rule: bookUrlRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                            if !bookUrl.starts(with: "http") && !bookUrl.isEmpty {
                                bookUrl = resolveUrl(bookUrl, baseUrl: baseUrl)
                            }
                            book.bookUrl = bookUrl
                        }
                        
                        if let coverRule = rule.coverUrl {
                            var coverUrl = try parseRuleValue(element: element, rule: coverRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                            if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                                coverUrl = resolveUrl(coverUrl, baseUrl: baseUrl)
                            }
                            book.coverUrl = coverUrl
                        }
                        
                        if let introRule = rule.intro {
                            book.intro = try parseRuleValue(element: element, rule: introRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                        }
                        
                        if let kindRule = rule.kind {
                            book.kind = try parseRuleValue(element: element, rule: kindRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                        }
                        
                        if let lastChapterRule = rule.lastChapter {
                            book.latestChapterTitle = try parseRuleValue(element: element, rule: lastChapterRule, html: elementHtml, baseUrl: baseUrl, jsLib: bookSource.jsLib)
                        }
                        
                        // 保存书源URL
                        book.bookSourceUrl = bookSource.bookSourceUrl
                        book.bookSourceName = bookSource.bookSourceName
                        
                        if !book.name.isEmpty && !book.bookUrl.isEmpty {
                            books.append(book)
                        }
                    }
                }
            }
        } catch {
            print("❌ JS解析失败: \(error)")
            throw error
        }
        
        return books
    }
    
    // 解析JS字段值
    private func parseJSField(_ jsValue: JSValue, rule: String, baseUrl: String, bookSource: BookSource) throws -> String {
        // 1. 处理 ## 分隔符（三段式：主规则##匹配正则##替换内容）
        let parts = rule.components(separatedBy: "##")
        var currentRule = rule
        var result = ""
        
        if parts.count >= 3 {
            // 第1部分：主规则（提取原始值）
            currentRule = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            // 第2部分：匹配正则（用于过滤）
            let matchPattern = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            // 第3部分：替换内容（JS代码）
            let replacement = parts[2...].joined(separator: "##").trimmingCharacters(in: .whitespacesAndNewlines)
            
            print("🔍 处理##规则 - 主规则: \(currentRule.prefix(50))...")
            print("🔍 处理##规则 - 正则: \(matchPattern.prefix(50))...")
            print("🔍 处理##规则 - 替换: \(replacement.prefix(100))...")
            
            // 执行主规则获取原始值
            result = try parseJSFieldSegments(jsValue, rule: currentRule, baseUrl: baseUrl, bookSource: bookSource)
            
            // 应用正则过滤
            if !matchPattern.isEmpty, let regex = try? NSRegularExpression(pattern: matchPattern, options: []) {
                let nsResult = result as NSString
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: nsResult.length),
                    withTemplate: ""
                )
                print("✅ 正则过滤后: \(result.prefix(50))...")
            }
            
            // 执行JS替换
            if !replacement.isEmpty {
                result = try parseJSFieldSegments(result, rule: replacement, baseUrl: baseUrl, bookSource: bookSource)
            }
            
            return result
        }
        
        // 2. 正常规则处理（无##分隔符）
        return try parseJSFieldSegments(jsValue, rule: currentRule, baseUrl: baseUrl, bookSource: bookSource)
    }
    
    // 解析JS字段片段（链式执行）
    private func parseJSFieldSegments(_ element: Any, rule: String, baseUrl: String, bookSource: BookSource) throws -> String {
        // 先处理模板语法 {{$.field}}
        var processedRule = rule
        
        // 提取所有 {{...}} 模板并替换
        let templatePattern = #"\{\{([^}]+)\}\}"#
        if let regex = try? NSRegularExpression(pattern: templatePattern, options: []) {
            var result = processedRule
            var offset = 0
            
            let nsRule = processedRule as NSString
            let matches = regex.matches(in: processedRule, options: [], range: NSRange(location: 0, length: nsRule.length))
            
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let originalRange = match.range(at: 0)
                    let templateContent = nsRule.substring(with: match.range(at: 1))
                    print("🔧 处理模板: {{\(templateContent)}}")
                    
                    // 简单实现：$.field → 访问 JSON 字段
                    var fieldValue = ""
                    if templateContent.hasPrefix("$.") {
                        let fieldName = String(templateContent.dropFirst(2))
                        if let jsVal = element as? JSValue, let prop = jsVal.forProperty(fieldName) {
                            fieldValue = prop.toString()
                        }
                    } else if templateContent.hasPrefix("$..") {
                        // $..text 表示递归查找所有 text 字段
                        let fieldName = String(templateContent.dropFirst(3))
                        if let jsVal = element as? JSValue, let prop = jsVal.forProperty(fieldName) {
                            fieldValue = prop.toString()
                        }
                    } else if templateContent == "source.bookSourceUrl" || templateContent.contains("source.") {
                        // 特殊处理 source 变量
                        fieldValue = baseUrl
                    }
                    
                    // 替换模板
                    let adjustedRange = NSRange(location: originalRange.location + offset, length: originalRange.length)
                    let nsResult = result as NSString
                    result = nsResult.replacingCharacters(in: adjustedRange, with: fieldValue)
                    offset += fieldValue.count - originalRange.length
                }
            }
            processedRule = result
        }
        
        print("🔧 模板处理后: \(processedRule.prefix(100))...")
        
        // 使用RuleAnalyzer检查是否包含JS
        let segments = RuleAnalyzer.splitRule(processedRule)
        
        // 链式执行所有片段
        var currentResult: Any = element
        
        for (index, segment) in segments.enumerated() {
            print("🔍 执行片段[\(index)]: mode=\(segment.mode), content=\(segment.content.prefix(50))...")
            
            if segment.mode == .js {
                // 执行JS规则
                var cleanRule = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 处理以 . 开头的链式调用（如 .replace()）
                if cleanRule.hasPrefix(".") {
                    // 将链式调用转换为完整表达式
                    cleanRule = "result\(cleanRule)"
                    print("🔗 转换链式调用: result\(segment.content.prefix(30))...")
                }
                
                // 将当前结果转换为 JSValue
                let jsContext = JSContext()!
                var jsResult: JSValue
                
                if let jsVal = currentResult as? JSValue {
                    jsResult = jsVal
                } else if let str = currentResult as? String {
                    jsResult = JSValue(object: str, in: jsContext)
                } else {
                    jsResult = JSValue(object: currentResult, in: jsContext)
                }
                
                currentResult = try JavaScriptEngine.shared.evaluate(
                    cleanRule,
                    variables: ["result": jsResult, "baseUrl": baseUrl, "java": jsResult],
                    jsLib: bookSource.jsLib
                )
            } else if segment.mode == .default {
                // CSS 选择器或 JSON 字段访问
                let property = segment.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !property.isEmpty {
                    if let jsVal = element as? JSValue, let prop = jsVal.forProperty(property) {
                        currentResult = prop.toString() ?? ""
                        print("✅ 访问字段 \(property): \(String(describing: currentResult).prefix(50))...")
                    }
                }
            }
        }
        
        // 转换为字符串
        if let jsVal = currentResult as? JSValue {
            return jsVal.toString()
        } else {
            return String(describing: currentResult)
        }
    }
    
    // 解析书籍信息
    private func parseBookInfo(html: String, bookUrl: String, rule: BookInfoRule?, bookSource: BookSource) throws -> Book {
        guard let rule = rule else {
            throw BookSourceError.noRule
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try parseBookInfoWithJSON(json: html, bookUrl: bookUrl, rule: rule, bookSource: bookSource)
        }
        
        let doc = try SwiftSoup.parse(html)
        
        // 临时存储变量的字典
        var variables: [String: String] = [:]
        
        // 处理init规则（@put保存变量）
        if let initRule = rule.`init` {
            variables = try parseInitRule(doc: doc, rule: initRule, html: html)
        }
        
        var name = ""
        var author = ""
        
        // 解析书名
        if let nameRule = rule.name {
            name = try parseFieldWithVariables(doc: doc, rule: nameRule, variables: variables, html: html, jsLib: bookSource.jsLib)
        }
        
        // 解析作者
        if let authorRule = rule.author {
            author = try parseFieldWithVariables(doc: doc, rule: authorRule, variables: variables, html: html, jsLib: bookSource.jsLib)
        }

        // 部分站点的详情规则会因页面改版失效，但页面仍保留标准 meta/h1 信息。
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = firstMetaContent(in: doc, propertySuffix: "book_name") ??
                firstText(in: doc, selector: "h1, title")
        }
        if author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            author = firstMetaContent(in: doc, propertySuffix: "author") ??
                firstText(in: doc, selector: "[rel=author], .author")
        }
        
        var book = Book(bookUrl: bookUrl, name: name, author: author)
        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
        
        // 解析简介
        if let introRule = rule.intro {
            book.intro = try parseFieldWithVariables(doc: doc, rule: introRule, variables: variables, html: html, jsLib: bookSource.jsLib)
        }
        
        // 解析封面
        if let coverRule = rule.coverUrl {
            var coverUrl = try parseFieldWithVariables(doc: doc, rule: coverRule, variables: variables, html: html, jsLib: bookSource.jsLib)
            if !coverUrl.starts(with: "http") && !coverUrl.isEmpty {
                coverUrl = resolveUrl(coverUrl, baseUrl: bookSource.bookSourceUrl)
            }
            book.coverUrl = coverUrl
        }
        
        // 解析分类
        if let kindRule = rule.kind {
            book.kind = try parseFieldWithVariables(doc: doc, rule: kindRule, variables: variables, html: html, jsLib: bookSource.jsLib)
        }
        
        // 解析目录URL
        if let tocRule = rule.tocUrl {
            let tocUrl = try parseFieldWithVariables(
                doc: doc,
                rule: tocRule,
                variables: variables,
                html: html,
                jsLib: bookSource.jsLib
            )
            let resolvedTocUrl = resolveUrl(tocUrl, baseUrl: bookUrl)
            book.tocUrl = resolvedTocUrl.isEmpty ? bookUrl : resolvedTocUrl
        } else {
            book.tocUrl = bookUrl
        }
        
        return book
    }

    private func firstMetaContent(in document: Document, propertySuffix: String) -> String? {
        guard let metaElements = try? document.select("meta[property]") else { return nil }
        for meta in metaElements {
            guard let property = try? meta.attr("property"),
                  property.lowercased().hasSuffix(propertySuffix.lowercased()),
                  let content = try? meta.attr("content") else {
                continue
            }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private func firstText(in document: Document, selector: String) -> String {
        guard let elements = try? document.select(selector),
              let element = elements.first(),
              let text = try? element.text() else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 使用JSON解析书籍信息
    private func parseBookInfoWithJSON(json: String, bookUrl: String, rule: BookInfoRule, bookSource: BookSource) throws -> Book {
        print("📦 使用JSON解析书籍信息")
        
        guard let data = json.data(using: .utf8) else {
            throw BookSourceError.parseError
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BookSourceError.parseError
        }
        
        // 使用init规则定位数据
        var bookData: [String: Any] = jsonObject
        if let initRule = rule.`init` {
            if let dataDict = try? LegadoRuleParser.jsonDictionary(from: json, rule: initRule) {
                bookData = dataDict
            }
        }
        
        // 解析基本信息
        let name = rule.name.map { extractJSONValue(from: bookData, rule: $0) } ?? ""
        let author = rule.author.map { extractJSONValue(from: bookData, rule: $0) } ?? ""
        
        var book = Book(bookUrl: bookUrl, name: name, author: author)
        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
        
        // 解析简介
        if let introRule = rule.intro {
            book.intro = extractJSONValue(from: bookData, rule: introRule)
        }
        
        // 解析封面
        if let coverRule = rule.coverUrl {
            var coverUrl = extractJSONValue(from: bookData, rule: coverRule)
            coverUrl = resolveUrl(coverUrl, baseUrl: bookSource.bookSourceUrl)
            book.coverUrl = coverUrl
        }
        
        // 解析分类 - 支持模板
        if let kindRule = rule.kind {
            var kind = kindRule
            kind = replaceTemplates(in: kind, with: bookData)
            book.kind = kind
        }
        
        // 解析tocUrl - 可能包含JS
        if let tocRule = rule.tocUrl {
            if containsJavaScript(tocRule) {
                // 例如: "$.bookid\n<js>\njava.put('bookid',result);\n\"/catalog?bookid=\"+result;\n</js>"
                let segments = RuleAnalyzer.splitRule(tocRule)
                var fieldValue = ""
                var tocUrl = ""
                
                // 先提取字段值
                for segment in segments {
                    if segment.mode != .js && !segment.content.isEmpty {
                        fieldValue = extractJSONValue(from: bookData, rule: segment.content)
                        break
                    }
                }
                
                // 执行JS - 保存bookid并构造URL
                for segment in segments {
                    if segment.mode == .js {
                        // 将bookid传递给JS环境
                        let variables: [String: Any] = ["result": fieldValue]
                        if let jsResult = try? JavaScriptEngine.shared.evaluate(segment.content, variables: variables) {
                            tocUrl = jsResult.toString() ?? ""
                        }
                        break
                    }
                }
                
                book.tocUrl = resolveUrl(tocUrl, baseUrl: bookSource.bookSourceUrl)
            } else {
                // 检查是否包含模板变量
                if tocRule.contains("{{") {
                    // 使用模板替换
                    let tocUrl = replaceTemplates(in: tocRule, with: bookData)
                    book.tocUrl = resolveUrl(tocUrl, baseUrl: bookSource.bookSourceUrl)
                } else {
                    // 作为字段名提取
                    let tocUrl = extractJSONValue(from: bookData, rule: tocRule)
                    book.tocUrl = resolveUrl(tocUrl, baseUrl: bookSource.bookSourceUrl)
                }
            }
        } else {
            book.tocUrl = bookUrl
        }
        
        print("✅ 书籍信息解析完成: \(name), tocUrl: \(book.tocUrl)")
        return book
    }
    
    // 解析章节列表
    private func parseChapterList(html: String, bookUrl: String, baseURL: String, rule: TocRule?, jsLib: String? = nil) throws -> [BookChapter] {
        guard let rule = rule, let chapterListRule = rule.chapterList else {
            throw BookSourceError.noRule
        }

        if RegexAllInOneParser.isAllInOneRule(chapterListRule) ||
            (chapterListRule.hasPrefix("-") &&
             RegexAllInOneParser.isAllInOneRule(String(chapterListRule.dropFirst()))) {
            return try parseChapterListWithAllInOne(html: html, bookUrl: bookUrl, baseURL: baseURL, rule: rule)
        }

        if containsJavaScript(chapterListRule) {
            return try parseChapterListWithJS(html: html, bookUrl: bookUrl, baseURL: baseURL, rule: rule, jsLib: jsLib)
        }
        
        // 检查是否是JSON响应
        if html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            // 使用JSON解析
            return try parseChapterListWithJSON(json: html, bookUrl: bookUrl, baseURL: baseURL, rule: rule)
        }
        
        let doc = try SwiftSoup.parse(html)
        
        // 处理特殊的章节列表选择器（支持@子选择器）
        var elements: Elements
        if chapterListRule.contains("@") {
            // @p、@dd@a 等表示继续选择子元素，必须保留原始 Element，
            // 不能先提取成纯文本后重新解析，否则 href 等属性会丢失。
            let selectedElements = try LegadoRuleParser.selectElements(
                html: html,
                rule: chapterListRule,
                baseURL: baseURL
            )
            elements = Elements()
            for element in selectedElements {
                elements.add(element)
            }
        } else {
            elements = try doc.select(chapterListRule)
        }
        
        var chapters: [BookChapter] = []
        var index = 0
        
        for element in elements {
            var title = ""
            var url = ""
            
            // 解析章节名 - 支持JS规则和@text等特殊属性
            if let nameRule = rule.chapterName {
                if containsJavaScript(nameRule) {
                    let elementHtml = try element.outerHtml()
                    title = try JavaScriptEngine.shared.parseJSRule(nameRule, html: elementHtml, baseUrl: baseURL, jsLib: jsLib)
                } else {
                    // 使用parseRuleValue支持@text等特殊属性
                    title = try parseRuleValue(element: element, rule: nameRule, html: html, baseUrl: baseURL, jsLib: jsLib)
                }
            } else {
                title = try element.text()
            }
            
            // 解析章节URL - 支持JS规则和@href等属性
            if let urlRule = rule.chapterUrl {
                if containsJavaScript(urlRule) {
                    let elementHtml = try element.outerHtml()
                    url = try JavaScriptEngine.shared.parseJSRule(urlRule, html: elementHtml, baseUrl: baseURL, jsLib: jsLib)
                } else {
                    // 使用parseRuleValue支持@href等属性
                    url = try parseRuleValue(element: element, rule: urlRule, html: html, baseUrl: baseURL, jsLib: jsLib)
                    print("🔍 [parseRuleValue返回] url=\(url), rule=\(urlRule)")
                }
            } else {
                url = try element.attr("href")
                print("🔍 [直接获取href] url=\(url)")
            }
            
            // 处理相对URL，使用resolveUrl确保正确拼接
            if !url.isEmpty {
                print("🔍 [章节URL解析] 原始: \(url), bookUrl: \(bookUrl)")
                url = resolveUrl(url, baseUrl: baseURL)
                print("🔍 [章节URL解析] 解析后: \(url)")
            }
            
            if !title.isEmpty && !url.isEmpty {
                var chapter = BookChapter(url: url, title: title, bookUrl: bookUrl, index: index)
                if let vipRule = rule.isVip, !vipRule.isEmpty {
                    chapter.isVip = isTruthy(try? parseRuleValue(element: element, rule: vipRule, html: html, baseUrl: baseURL))
                }
                if let payRule = rule.isPay, !payRule.isEmpty {
                    chapter.isPay = isTruthy(try? parseRuleValue(element: element, rule: payRule, html: html, baseUrl: baseURL))
                }
                if let updateRule = rule.updateTime, !updateRule.isEmpty {
                    chapter.tag = try? parseRuleValue(element: element, rule: updateRule, html: html, baseUrl: baseURL)
                }
                chapters.append(chapter)
                index += 1
            }
        }
        
        return chapters
    }

    private func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "vip", "付费", "收费"].contains(
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private func parseChapterListWithAllInOne(
        html: String,
        bookUrl: String,
        baseURL: String,
        rule: TocRule
    ) throws -> [BookChapter] {
        guard let rawRule = rule.chapterList else { throw BookSourceError.noRule }
        let reverse = rawRule.hasPrefix("-")
        let listRule = reverse ? String(rawRule.dropFirst()) : rawRule
        let matches = try RegexAllInOneParser.parse(rule: listRule, content: html)
        func read(_ field: String?, from match: [String: String]) -> String {
            guard let field else { return "" }
            if let direct = match[field.trimmingCharacters(in: .whitespacesAndNewlines)] {
                return direct
            }
            let pattern = #"\$(\d+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return field }
            var result = field
            let source = field as NSString
            for item in regex.matches(in: field, range: NSRange(location: 0, length: source.length)).reversed() {
                let key = "$\(source.substring(with: item.range(at: 1)))"
                result = (result as NSString).replacingCharacters(in: item.range, with: match[key] ?? "")
            }
            return result
        }

        var chapters = matches.compactMap { match -> BookChapter? in
            let title = read(rule.chapterName, from: match)
            let url = resolveUrl(read(rule.chapterUrl, from: match), baseUrl: baseURL)
            guard !title.isEmpty, !url.isEmpty else { return nil }
            return BookChapter(url: url, title: title, bookUrl: bookUrl, index: 0)
        }
        if reverse { chapters.reverse() }
        for index in chapters.indices { chapters[index].index = index }
        return chapters
    }

    /// 解析由 JavaScript 返回的章节数组，兼容 JSON 字段和 JS 组合规则。
    private func parseChapterListWithJS(html: String, bookUrl: String, baseURL: String, rule: TocRule, jsLib: String? = nil) throws -> [BookChapter] {
        guard let chapterListRule = rule.chapterList else { throw BookSourceError.noRule }
        let segments = RuleAnalyzer.splitRule(chapterListRule)
        var currentResult: Any = html

        for segment in segments where segment.mode == .json {
            if let objects = try? LegadoRuleParser.jsonObjects(from: html, rule: segment.content) {
                currentResult = objects
            }
        }

        guard let jsSegment = segments.first(where: { $0.mode == .js }) else {
            throw BookSourceError.noRule
        }
        let result = try JavaScriptEngine.shared.evaluate(
            jsSegment.content,
            variables: ["result": currentResult, "baseUrl": baseURL, "html": html],
            jsLib: jsLib
        )
        guard result.isArray else { throw BookSourceError.parseError }

        var chapters: [BookChapter] = []
        let count = Int(result.forProperty("length").toInt32())
        for index in 0..<count {
            guard let item = result.atIndex(index) else { continue }
            let title = try jsChapterField(item, rule: rule.chapterName, defaultValue: "第 \(index + 1) 章", baseUrl: baseURL, jsLib: jsLib)
            let rawURL = try jsChapterField(item, rule: rule.chapterUrl, defaultValue: "", baseUrl: baseURL, jsLib: jsLib)
            let url = resolveUrl(rawURL, baseUrl: baseURL)
            guard !title.isEmpty, !url.isEmpty else { continue }
            chapters.append(BookChapter(url: url, title: title, bookUrl: bookUrl, index: chapters.count))
        }
        return chapters
    }

    private func jsChapterField(_ item: JSValue, rule: String?, defaultValue: String, baseUrl: String, jsLib: String? = nil) throws -> String {
        guard let rule, !rule.isEmpty else {
            return defaultValue.isEmpty ? (item.toString() ?? "") : defaultValue
        }
        var current = item
        for segment in RuleAnalyzer.splitRule(rule) {
            switch segment.mode {
            case .js:
                current = try JavaScriptEngine.shared.evaluate(
                    segment.content,
                    variables: ["result": current, "baseUrl": baseUrl],
                    jsLib: jsLib
                )
            case .default, .json:
                var path = segment.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "@Json:", with: "")
                    .replacingOccurrences(of: "$.", with: "")
                if path.hasPrefix("@") { path.removeFirst() }
                for component in path.split(separator: ".") {
                    if let next = current.forProperty(String(component)) {
                        current = next
                    }
                }
            case .xpath, .regex:
                break
            }
        }
        return current.toString() ?? defaultValue
    }
    
    // 使用JSON解析章节列表
    private func parseChapterListWithJSON(json: String, bookUrl: String, baseURL: String, rule: TocRule) throws -> [BookChapter] {
        print("📦 使用JSON解析章节列表")

        // 从bookUrl中提取bookid并保存到JS缓存
        // bookUrl格式可能是: http://69shuba.qingtian618.com/catalog?bookid=89023
        if let urlComponents = URLComponents(string: bookUrl),
           let queryItems = urlComponents.queryItems,
           let bookidItem = queryItems.first(where: { $0.name == "bookid" }),
           let bookid = bookidItem.value {
            print("📦 从URL提取bookid并保存: \(bookid)")
            // 保存到JS环境的缓存中
            _ = try? JavaScriptEngine.shared.evaluate("java.put('bookid', '\(bookid)');", variables: [:])
        }

        var chapters: [BookChapter] = []

        // 获取章节数组
        guard let chapterListRule = rule.chapterList else {
            throw BookSourceError.noRule
        }

        print("📦 尝试获取章节数组，规则: \(chapterListRule)")

        guard let chapterArray = try? LegadoRuleParser.jsonObjects(from: json, rule: chapterListRule),
              !chapterArray.isEmpty else {
            print("❌ 无法从JSON中获取章节数组: \(chapterListRule)")
            return chapters
        }
        
        print("✅ 找到 \(chapterArray.count) 个章节")

        // 从 bookUrl 中提取 book_id（如果存在）
        var bookId: String? = nil
        if let urlComponents = URLComponents(string: bookUrl),
           let pathComponents = urlComponents.path.components(separatedBy: "/").last {
            bookId = pathComponents
            print("📦 从 bookUrl 提取 book_id: \(bookId ?? "nil")")
        }

        // 解析每个章节
        for (index, chapterData) in chapterArray.enumerated() {
            var title = ""
            var url = ""

            // 解析章节名
            if let nameRule = rule.chapterName {
                // 检查是否包含正则替换规则（##）
                if nameRule.contains("##") {
                    let parts = nameRule.components(separatedBy: "##")
                    if parts.count >= 2 {
                        // 第一部分是字段名，第二部分是正则替换规则
                        let fieldRule = parts[0]
                        let regexRule = parts[1]

                        // 提取字段值
                        var fieldValue = extractJSONValue(from: chapterData, rule: fieldRule)

                        // 应用正则替换（移除匹配的内容）
                        let patterns = regexRule.components(separatedBy: "|")
                        for pattern in patterns {
                            if !pattern.isEmpty {
                                fieldValue = fieldValue.replacingOccurrences(
                                    of: pattern,
                                    with: "",
                                    options: .regularExpression
                                )
                            }
                        }

                        title = fieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        title = extractJSONValue(from: chapterData, rule: nameRule)
                    }
                } else {
                    title = extractJSONValue(from: chapterData, rule: nameRule)
                }

                print("📖 章节 \(index): \(title)")
            }

            // 解析章节URL - 可能包含JS或模板变量
            if let urlRule = rule.chapterUrl {
                // 69书吧的chapterUrl规则: "$.itemid\n<js>\nlet bookid = java.get('bookid');\n`/content?bookid=${bookid}&itemid=${result}`;\n</js>"
                if containsJavaScript(urlRule) {
                    let segments = RuleAnalyzer.splitRule(urlRule)
                    var fieldValue = ""

                    // 先提取字段值
                    for segment in segments {
                        if segment.mode != .js && !segment.content.isEmpty {
                            fieldValue = extractJSONValue(from: chapterData, rule: segment.content)
                            break
                        }
                    }

                    // 执行JS构造URL
                    for segment in segments {
                        if segment.mode == .js {
                            let variables: [String: Any] = ["result": fieldValue]
                            if let jsResult = try? JavaScriptEngine.shared.evaluate(segment.content, variables: variables, jsLib: nil) {
                                url = jsResult.toString() ?? ""
                            }
                            break
                        }
                    }
                } else if urlRule.contains("{{") {
                    // 包含模板变量，需要替换
                    // 创建合并的数据字典（章节数据 + book_id）
                    var mergedData = chapterData
                    if let bookId = bookId {
                        mergedData["book_id"] = bookId
                    }
                    url = replaceTemplates(in: urlRule, with: mergedData)
                } else {
                    url = extractJSONValue(from: chapterData, rule: urlRule)
                }
            }
            
            // 处理相对URL
            if !url.isEmpty {
                url = resolveUrl(url, baseUrl: baseURL)
                
                var chapter = BookChapter(url: url, title: title, bookUrl: bookUrl, index: index)
                if let vipRule = rule.isVip, !vipRule.isEmpty {
                    chapter.isVip = isTruthy(extractJSONValue(from: chapterData, rule: vipRule))
                }
                if let payRule = rule.isPay, !payRule.isEmpty {
                    chapter.isPay = isTruthy(extractJSONValue(from: chapterData, rule: payRule))
                }
                if let updateRule = rule.updateTime, !updateRule.isEmpty {
                    chapter.tag = extractJSONValue(from: chapterData, rule: updateRule)
                }
                chapters.append(chapter)
            }
        }
        
        print("✅ 解析完成，共 \(chapters.count) 个章节")
        return chapters
    }
    
    // 解析正文内容
    private func parseContent(html: String, rule: ContentRule?, jsLib: String? = nil) throws -> String {
        guard let rule = rule, let contentRule = rule.content else {
            throw BookSourceError.noRule
        }

        // sourceRegex 在 Android 端用于 WebView 资源嗅探；macOS 没有 WebView
        // 资源回调，因此保留原始响应，避免把 URL 正则误当成正文正则。
        let source = html

        if RegexOnlyOneParser.isOnlyOneRule(contentRule),
           let result = try RegexOnlyOneParser.parse(rule: contentRule, content: source) {
            return result
        }
        
        // 检查是否是JSON响应
        if source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return try parseContentWithJSON(json: source, rule: rule)
        }
        
        // 检查是否使用JS规则
        if containsJavaScript(contentRule) {
            let content = try JavaScriptEngine.shared.parseJSRule(contentRule, html: source, baseUrl: "", jsLib: jsLib)
            
            // 应用替换规则
            if let replaceRegex = rule.replaceRegex {
                return applyReplaceRule(content: content, replaceRule: replaceRegex)
            }
            
            return content
        }
        
        // CSS选择器解析
        let doc = try SwiftSoup.parse(source)
        
        // 使用parseRuleValue处理规则，支持@text/@html等特殊语法
        let dummyElement = try doc.select("html").first()!
        var content = try parseRuleValue(element: dummyElement, rule: contentRule, html: source, baseUrl: "", jsLib: jsLib)
        
        // 如果内容本身是HTML，需要提取纯文本并保留段落结构
        if !contentRule.contains("@text") {
            // 解析HTML内容
            let contentDoc = try SwiftSoup.parse(content)
            
            // 遍历所有<p>标签，提取文本并添加换行
            var paragraphs: [String] = []
            let pElements = try contentDoc.select("p")
            for p in pElements {
                let text = try p.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    paragraphs.append(text)
                }
            }
            
            // 如果没有<p>标签，尝试其他方式
            if paragraphs.isEmpty {
                // 处理<br>换行
                content = content.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
                content = content.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
                content = content.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
                content = try SwiftSoup.parse(content).text()
            } else {
                // 用双换行连接段落（段落间有空行）
                content = paragraphs.joined(separator: "\n\n")
            }
            
            // 清理首尾空白
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 应用替换规则
        if let replaceRegex = rule.replaceRegex {
            content = applyReplaceRule(content: content, replaceRule: replaceRegex)
        }
        
        return content
    }
    
    // 使用JSON解析章节内容
    private func parseContentWithJSON(json: String, rule: ContentRule) throws -> String {
        print("📦 使用JSON解析章节内容")
        print("📦 原始JSON前300字符: \(json.prefix(300))")
        print("📦 Content规则: \(rule.content ?? "nil")")
        
        guard let contentRule = rule.content else {
            print("❌ 没有content规则")
            throw BookSourceError.noRule
        }

        var content = (try? LegadoRuleParser.jsonValue(from: json, rule: contentRule)) ?? ""
        if content.isEmpty,
           let dataContent = try? LegadoRuleParser.jsonValue(from: json, rule: "$.data") {
            content = dataContent
        }
        if content.isEmpty {
            content = (try? LegadoRuleParser.jsonValue(from: json, rule: "$.content")) ?? ""
        }
        
        if content.isEmpty || content == "Optional(<null>)" || content == "<null>" {
            print("❌ 未找到有效内容")
            throw BookSourceError.parseError
        }
        
        print("✅ 最终返回内容长度: \(content.count)")
        return content
    }
    
    // 应用替换规则
    private func applyReplaceRule(content: String, replaceRule: String) -> String {
        var result = content
        for line in replaceRule.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "##")
            guard parts.count >= 2 else { continue }
            var index = parts.first?.isEmpty == true ? 1 : 0
            while index < parts.count {
                let pattern = parts[index]
                guard !pattern.isEmpty else { index += 1; continue }
                let replacement = index + 1 < parts.count ? parts[index + 1] : ""
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                    result = regex.stringByReplacingMatches(
                        in: result,
                        range: NSRange(location: 0, length: result.utf16.count),
                        withTemplate: replacement
                    )
                } else {
                    result = result.replacingOccurrences(of: pattern, with: replacement)
                }
                index += 2
            }
        }
        return result
    }

    // 解析请求头
    private func parseHeaders(_ headerStr: String?) -> [String: String]? {
        guard let headerStr = headerStr, !headerStr.isEmpty else {
            return nil
        }
        
        // 处理 @js: 动态请求头。Android 书源常用它读取 token/cookie 后返回对象。
        if headerStr.hasPrefix("@js:") {
            let script = String(headerStr.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = try? JavaScriptEngine.shared.evaluate(script),
               let dictionary = value.toDictionary() as? [String: Any] {
                return dictionary.reduce(into: [String: String]()) { result, item in
                    result[item.key] = String(describing: item.value)
                }
            }
            if let value = try? JavaScriptEngine.shared.evaluateRule(script),
               let data = value.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return json
            }
            print("⚠️ 动态 header 未返回有效对象")
            return nil
        }
        
        var headers: [String: String] = [:]
        
        // 尝试解析JSON格式的请求头
        if let data = headerStr.data(using: .utf8),
           let jsonHeaders = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return jsonHeaders.reduce(into: [String: String]()) { result, item in
                result[item.key] = String(describing: item.value)
            }
        }
        
        // 解析键值对格式
        let lines = headerStr.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return headers.isEmpty ? nil : headers
    }
    
    // 解析URL中的简单表达式（如 {{ ( page - 1 ) * 10 }}）
    private func evaluateSimpleExpressions(in url: String, page: Int) -> String {
        var result = url
        
        // 匹配 {{ expression }} 格式
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        
        let nsString = url as NSString
        let matches = regex.matches(in: url, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 从后向前替换，避免索引问题
        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                let fullRange = match.range(at: 0)
                let exprRange = match.range(at: 1)
                var expression = nsString.substring(with: exprRange).trimmingCharacters(in: .whitespaces)
                
                // 处理 Android 阅读特有的格式: key;java.put("key",key)
                // 提取分号前面的变量名
                var needsReplacement = false
                if expression.contains(";") {
                    let parts = expression.components(separatedBy: ";")
                    if let firstPart = parts.first?.trimmingCharacters(in: .whitespaces), !firstPart.isEmpty {
                        expression = firstPart
                        needsReplacement = true
                        print("⚠️ 从复合表达式中提取变量: \(expression)")
                    }
                }
                
                // 检查是否是简单变量名（如 key, page）
                let simpleVarPattern = "^[a-zA-Z_][a-zA-Z0-9_]*$"
                if let varRegex = try? NSRegularExpression(pattern: simpleVarPattern, options: []),
                   varRegex.firstMatch(in: expression, options: [], range: NSRange(location: 0, length: expression.count)) != nil {
                    // 是简单变量名
                    if needsReplacement {
                        // 从复合表达式中提取的变量，需要替换为简单格式 {{variable}}
                        result = (result as NSString).replacingCharacters(in: fullRange, with: "{{\(expression)}}")
                    }
                    // 保留简单变量让后续替换
                    continue
                }
                
                // 计算简单的数学表达式
                if let value = evaluateMathExpression(expression, page: page) {
                    result = (result as NSString).replacingCharacters(in: fullRange, with: "\(value)")
                } else {
                    // 对于无法计算的表达式，尝试提取默认值
                    print("⚠️ 无法计算表达式，尝试使用默认值: \(expression)")
                    
                    // 尝试提取默认值 (pattern: expression || defaultValue)
                    if let orIndex = expression.range(of: "||") {
                        let defaultPart = String(expression[orIndex.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if let defaultValue = Int(defaultPart) {
                            result = (result as NSString).replacingCharacters(in: fullRange, with: "\(defaultValue)")
                        } else {
                            // 默认值不是数字，可能是字符串，保留它
                            result = (result as NSString).replacingCharacters(in: fullRange, with: defaultPart)
                        }
                    } else {
                        // 无法处理，移除整个表达式（保留空字符串）
                        result = (result as NSString).replacingCharacters(in: fullRange, with: "")
                    }
                }
            }
        }
        
        // 处理简单的 {{page}} 和 {page} 变量
        result = result
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "{page}", with: "\(page)")
        
        return result
    }
    
    // 计算简单的数学表达式（支持 page 变量）
    private func evaluateMathExpression(_ expr: String, page: Int) -> Int? {
        var expression = expr.trimmingCharacters(in: .whitespaces)

        // 检查是否包含Android阅读特有的语法（这些无法用NSExpression计算）
        let unsupportedPatterns = [
            "Map\\(",           // Map("key")
            "java\\.",          // java.put(), java.get()
            "cookie\\.",        // cookie.removeCookie()
            "source\\.",        // source.getKey(), source.getVariable()
            "getKey\\(",        // getKey()
            "getVariable\\(",   // getVariable()
            "removeCookie\\(",  // removeCookie()
            "encodeURI",        // encodeURI()
            "JSON\\.",          // JSON.stringify()
            "String\\(",        // String()
            "org\\.jsoup",      // org.jsoup.Jsoup
            "\\.split\\(",      // .split(",")
            "\\.match\\(",      // .match()
            "\\.replace\\(",    // .replace()
            "\\|\\|",           // || 默认值运算符
            "\\?",              // 三元运算符
            ":",                // 三元运算符的:
            "let ",             // JavaScript变量声明
            "var ",             // JavaScript变量声明
            "const ",           // JavaScript变量声明
            "=>",               // 箭头函数
            "function",         // 函数声明
            "\\$\\{",           // 模板字符串
        ]

        for pattern in unsupportedPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: expression, options: [], range: NSRange(location: 0, length: expression.count)) != nil {
                print("⚠️ 表达式包含不支持的语法: \(expr)")
                return nil
            }
        }

        // 检查是否只包含安全的字符（数字、运算符、括号、page变量）
        let safePattern = "^[0-9+\\-*/()\\s]*$|^[0-9+\\-*/()\\spage]*$"
        let testExpression = expression.replacingOccurrences(of: "page", with: "")
        if let safeRegex = try? NSRegularExpression(pattern: safePattern, options: []),
           safeRegex.firstMatch(in: testExpression, options: [], range: NSRange(location: 0, length: testExpression.count)) == nil {
            print("⚠️ 表达式包含不安全的字符: \(expr)")
            return nil
        }

        // 替换 page 变量
        expression = expression.replacingOccurrences(of: "page", with: "\(page)")

        // 移除所有空格
        expression = expression.replacingOccurrences(of: " ", with: "")

        // 最后检查：确保只包含数字和运算符
        let finalPattern = "^[0-9+\\-*/()]+$"
        if let finalRegex = try? NSRegularExpression(pattern: finalPattern, options: []),
           finalRegex.firstMatch(in: expression, options: [], range: NSRange(location: 0, length: expression.count)) == nil {
            print("⚠️ 表达式格式不正确: \(expression)")
            return nil
        }

        // 尝试使用 NSExpression 计算
        let exp = NSExpression(format: expression)
        if let result = exp.expressionValue(with: nil, context: nil) as? NSNumber {
            return result.intValue
        }

        print("⚠️ 无法计算表达式: \(expression)")
        return nil
    }

    // 转换Android阅读的选择器语法为标准CSS选择器
    private func convertToStandardCSSSelector(_ selector: String) -> String {
        var result = selector

        // 处理 class.xxx -> .xxx
        result = result.replacingOccurrences(of: #"class\.([a-zA-Z0-9_-]+)"#, with: ".$1", options: .regularExpression)

        // 处理 id.xxx -> #xxx
        result = result.replacingOccurrences(of: #"id\.([a-zA-Z0-9_-]+)"#, with: "#$1", options: .regularExpression)

        // 处理 tag.xxx -> xxx
        result = result.replacingOccurrences(of: #"tag\.([a-zA-Z0-9_-]+)"#, with: "$1", options: .regularExpression)

        return result
    }

    // 解析相对URL（补全协议和域名）
    private func resolveUrl(_ urlString: String, baseUrl: String) -> String {
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespaces)
        let trimmedBase = baseUrl.trimmingCharacters(in: .whitespaces)
        
        print("🔗 [resolveUrl] 输入: url=\(trimmedUrl), baseUrl=\(trimmedBase)")
        
        // 如果已经是完整URL，直接返回
        if trimmedUrl.hasPrefix("http://") || trimmedUrl.hasPrefix("https://") {
            print("🔗 [resolveUrl] 已是完整URL，直接返回")
            return trimmedUrl
        }
        
        // 解析基础URL
        guard let base = URL(string: trimmedBase) else {
            print("❌ resolveUrl: 无法解析 baseUrl=\(trimmedBase)")
            return trimmedUrl
        }
        
        // 如果是相对路径，组合基础URL
        if trimmedUrl.hasPrefix("/") {
            // 绝对路径（相对于域名根目录）
            if let scheme = base.scheme, let host = base.host {
                let port = base.port.map { ":\($0)" } ?? ""
                return "\(scheme)://\(host)\(port)\(trimmedUrl)"
            }
        } else {
            // 相对路径（相对于当前目录）
            if let resolved = URL(string: trimmedUrl, relativeTo: base) {
                return resolved.absoluteString
            }
        }
        
        return trimmedUrl
    }
    
    // 检查规则是否包含JavaScript代码
    private func containsJavaScript(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("@js:") || 
               trimmed.hasPrefix("<js>") || 
               trimmed.contains("<js>") ||
               trimmed.hasPrefix("{{") && trimmed.contains("@js")
    }
}

// 搜索书籍结果
struct SearchBook: Identifiable {
    let id = UUID()
    var name: String = ""
    var author: String = ""
    var bookUrl: String = ""
    var coverUrl: String?
    var intro: String?
    var kind: String?
    var latestChapterTitle: String?
    var wordCount: String?
    var bookSourceUrl: String = "" // 书源URL，用于后续获取详情
    var bookSourceName: String = "" // 书源名称，用于显示
}

// MARK: - @put/@get 变量支持
extension BookSourceEngine {
    /// 解析init规则，提取并保存变量
    private func parseInitRule(doc: Document, rule: String, html: String) throws -> [String: String] {
        var variables: [String: String] = [:]
        
        // 检查是否是@put规则
        if rule.hasPrefix("@put:") {
            let content = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            // 解析 {key1:"selector1", key2:"selector2"} 格式
            if content.hasPrefix("{") && content.hasSuffix("}") {
                let jsonContent = content.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
                // 规则值可能包含 CSS 逗号、属性选择器或 JS 片段，不能直接按逗号切分。
                for pair in splitPutEntries(jsonContent) {
                    guard let separator = firstTopLevelColon(in: pair) else { continue }
                    let key = pair[..<separator]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    var selector = pair[pair.index(after: separator)...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if selector.count >= 2,
                       (selector.first == "\"" && selector.last == "\"") ||
                       (selector.first == "'" && selector.last == "'") {
                        selector.removeFirst()
                        selector.removeLast()
                    }

                    guard !key.isEmpty, !selector.isEmpty else { continue }

                    do {
                        let value = try parseRuleValue(element: doc, rule: selector, html: html, baseUrl: "")
                        variables[key] = value
                        print("  📌 保存变量: \(key) = \(value.prefix(50))")
                    } catch {
                        print("  ⚠️ 解析变量\(key)失败: \(error)")
                    }
                }
            }
        }
        
        return variables
    }

    private func splitPutEntries(_ value: String) -> [Substring] {
        var entries: [Substring] = []
        var start = value.startIndex
        var index = value.startIndex
        var depth = 0
        var quote: Character?
        var escaped = false

        while index < value.endIndex {
            let character = value[index]
            if let quoteCharacter = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == quoteCharacter {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "(" || character == "{" {
                depth += 1
            } else if character == "]" || character == ")" || character == "}" {
                depth = max(0, depth - 1)
            } else if character == "," && depth == 0 {
                entries.append(value[start..<index])
                start = value.index(after: index)
            }
            index = value.index(after: index)
        }

        entries.append(value[start..<value.endIndex])
        return entries
    }

    private func firstTopLevelColon(in value: Substring) -> String.Index? {
        var index = value.startIndex
        var depth = 0
        var quote: Character?
        var escaped = false

        while index < value.endIndex {
            let character = value[index]
            if let quoteCharacter = quote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == quoteCharacter {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "(" || character == "{" {
                depth += 1
            } else if character == "]" || character == ")" || character == "}" {
                depth = max(0, depth - 1)
            } else if character == ":" && depth == 0 {
                return index
            }
            index = value.index(after: index)
        }

        return nil
    }
    
    /// 解析字段，支持@get从变量获取
    private func parseFieldWithVariables(doc: Document, rule: String, variables: [String: String], html: String, jsLib: String? = nil) throws -> String {
        // 检查是否是@get规则
        if rule.hasPrefix("@get:") {
            var varName = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if varName.hasPrefix("{") && varName.hasSuffix("}") {
                varName.removeFirst()
                varName.removeLast()
            }
            varName = varName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = variables[varName] {
                return value
            }
            print("  ⚠️ 变量\(varName)未找到")
            return ""
        }

        if rule.contains("{{") {
            return try parseHTMLTemplateRule(
                rule,
                document: doc,
                html: html,
                baseURL: "",
                jsLib: jsLib
            )
        }
        
        // 普通CSS选择器
        return try parseRuleValue(element: doc, rule: rule, html: html, baseUrl: "", jsLib: jsLib)
    }

    /// 解析 HTML 书籍详情规则中的 {{...}} 模板。
    ///
    /// 例如 `🔖 {{@.w_txt li.4@textNodes}}` 中的 `@` 表示从当前文档执行
    /// CSS/JSoup 规则；字符串拼接模板则交给 JavaScript 兼容层执行。
    private func parseHTMLTemplateRule(
        _ rule: String,
        document: Document,
        html: String,
        baseURL: String,
        jsLib: String?
    ) throws -> String {
        let parts = rule.components(separatedBy: "##")
        let template = parts.first ?? rule
        let pattern = parts.count >= 3 ? parts[1] : nil
        let replacement = parts.count >= 3 ? parts.dropFirst(2).joined(separator: "##") : nil

        guard let regex = try? NSRegularExpression(
            pattern: #"\{\{([\s\S]*?)\}\}"#,
            options: []
        ) else {
            return template
        }

        var result = template
        let source = template as NSString
        let matches = regex.matches(
            in: template,
            options: [],
            range: NSRange(location: 0, length: source.length)
        )

        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let expression = source.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = try evaluateHTMLTemplateExpression(
                expression,
                document: document,
                html: html,
                baseURL: baseURL,
                jsLib: jsLib
            )
            result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: value)
        }

        if let pattern, let replacement,
           let cleanRegex = try? NSRegularExpression(pattern: pattern, options: []) {
            let resultSource = result as NSString
            result = cleanRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: resultSource.length),
                withTemplate: replacement
            )
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evaluateHTMLTemplateExpression(
        _ expression: String,
        document: Document,
        html: String,
        baseURL: String,
        jsLib: String?
    ) throws -> String {
        if expression.hasPrefix("@") {
            let selectorRule = String(expression.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return try parseRuleValue(
                element: document,
                rule: selectorRule,
                html: html,
                baseUrl: baseURL,
                jsLib: jsLib
            )
        }

        if expression.hasPrefix("@js:") || expression.hasPrefix("<js>") {
            return try JavaScriptEngine.shared.parseJSRule(
                expression,
                html: html,
                baseUrl: baseURL,
                jsLib: jsLib
            )
        }

        // 书源常用的 {{'\\n' + '​'}} 等常量/拼接表达式。
        if let value = try? JavaScriptEngine.shared.evaluate(expression, variables: [:], jsLib: jsLib),
           let text = value.toString() {
            return text
        }

        // 无法执行的模板保留为空，避免把 {{...}} 当成 CSS 选择器继续解析。
        return ""
    }
}

// 书源错误
enum BookSourceError: Error, LocalizedError {
    case noSearchUrl
    case noRule
    case parseError
    case unsupportedJavaScript(sourceName: String)
    case unsupportedJavaScriptInRule
    
    var errorDescription: String? {
        switch self {
        case .noSearchUrl:
            return "书源未配置搜索地址"
        case .noRule:
            return "书源规则不完整"
        case .parseError:
            return "解析失败"
        case .unsupportedJavaScript(let sourceName):
            return "书源【\(sourceName)】使用了当前 macOS 版本无法执行的 Java/WebView 扩展。"
        case .unsupportedJavaScriptInRule:
            return "该规则依赖 Android WebView 或 Java 类扩展，macOS 版本无法执行。"
        }
    }
}
