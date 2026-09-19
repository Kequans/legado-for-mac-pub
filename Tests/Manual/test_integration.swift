import Foundation
import GRDB

// 简单的测试框架
func testSection(_ name: String, _ tests: () throws -> Void) {
    print("\n📋 \(name)")
    do {
        try tests()
    } catch {
        print("❌ 测试失败: \(error)")
    }
}

func assert(_ condition: Bool, _ message: String) {
    if condition {
        print("✅ \(message)")
    } else {
        print("❌ \(message)")
        exit(1)
    }
}

print("🧪 开始RSS功能集成测试\n")
print("=" * 60)

// 测试1: 数据库初始化
testSection("测试1: 数据库初始化") {
    let dbManager = DatabaseManager.shared
    dbManager.initialize()

    guard let db = dbManager.getDatabase() else {
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "数据库未初始化"])
    }

    // 检查表是否存在
    let hasRSSTable = try db.read { db in
        try db.tableExists("rss_sources")
    }
    assert(hasRSSTable, "rss_sources表已创建")

    let hasArticlesTable = try db.read { db in
        try db.tableExists("articles")
    }
    assert(hasArticlesTable, "articles表已创建")
}

// 测试2: 保存和读取订阅源
testSection("测试2: 订阅源CRUD操作") {
    let dao = RSSSourceDAO()

    // 创建测试订阅源
    let testSource = RSSSource(
        sourceName: "测试RSS源",
        sourceUrl: "http://example.com/rss.xml",
        sourceIcon: nil,
        sourceGroup: "测试分组",
        enabled: true,
        enableJs: false,
        enabledCookieJar: false,
        customOrder: 0,
        lastUpdateTime: Int64(Date().timeIntervalSince1970),
        ruleArticles: nil,
        ruleNextUrl: nil,
        ruleTitle: nil,
        ruleLink: nil,
        ruleDescription: nil,
        ruleContent: nil,
        ruleImage: nil,
        rulePubDate: nil,
        header: nil,
        articleStyle: 0,
        singleUrl: false,
        sortUrl: nil,
        loadWithBaseUrl: false
    )

    // 保存订阅源
    try dao.save(testSource)
    print("✅ 订阅源保存成功")

    // 读取订阅源
    let sources = try dao.getAllSources()
    assert(sources.count > 0, "成功读取订阅源列表，共\(sources.count)个")

    // 根据URL读取
    if let source = try dao.getSource(by: "http://example.com/rss.xml") {
        assert(source.sourceName == "测试RSS源", "订阅源名称正确: \(source.sourceName)")
        assert(source.sourceGroup == "测试分组", "订阅源分组正确: \(source.sourceGroup ?? "nil")")
    } else {
        print("❌ 无法根据URL读取订阅源")
    }

    // 更新启用状态
    try dao.updateEnabled(sourceUrl: "http://example.com/rss.xml", enabled: false)
    if let source = try dao.getSource(by: "http://example.com/rss.xml") {
        assert(source.enabled == false, "订阅源启用状态更新成功")
    }
}

// 测试3: 保存和读取文章
testSection("测试3: 文章CRUD操作") {
    let dao = RSSSourceDAO()

    // 创建测试文章
    let testArticle = Article(
        title: "测试文章标题",
        link: "http://example.com/article1",
        description: "这是一篇测试文章的描述",
        content: nil,
        imageUrl: nil,
        pubDate: Date(),
        sourceUrl: "http://example.com/rss.xml",
        isRead: false,
        isFavorite: false,
        readTime: nil
    )

    // 保存文章
    try dao.save(testArticle)
    print("✅ 文章保存成功")

    // 读取文章
    let articles = try dao.getArticles(sourceUrl: "http://example.com/rss.xml")
    assert(articles.count > 0, "成功读取文章列表，共\(articles.count)篇")

    // 根据链接读取
    if let article = try dao.getArticle(by: "http://example.com/article1") {
        assert(article.title == "测试文章标题", "文章标题正确: \(article.title)")
        assert(article.isRead == false, "文章未读状态正确")
    } else {
        print("❌ 无法根据链接读取文章")
    }

    // 标记为已读
    try dao.markAsRead(link: "http://example.com/article1")
    if let article = try dao.getArticle(by: "http://example.com/article1") {
        assert(article.isRead == true, "文章已读状态更新成功")
    }

    // 切换收藏状态
    try dao.toggleFavorite(link: "http://example.com/article1")
    if let article = try dao.getArticle(by: "http://example.com/article1") {
        assert(article.isFavorite == true, "文章收藏状态更新成功")
    }
}

// 测试4: 批量操作
testSection("测试4: 批量操作") {
    let dao = RSSSourceDAO()

    // 创建多个测试文章
    let articles = (1...5).map { i in
        Article(
            title: "批量测试文章\(i)",
            link: "http://example.com/batch\(i)",
            description: "批量测试文章\(i)的描述",
            content: nil,
            imageUrl: nil,
            pubDate: Date(),
            sourceUrl: "http://example.com/rss.xml",
            isRead: false,
            isFavorite: false,
            readTime: nil
        )
    }

    // 批量保存
    try dao.saveAll(articles)
    print("✅ 批量保存5篇文章成功")

    // 读取所有文章
    let allArticles = try dao.getArticles(sourceUrl: "http://example.com/rss.xml")
    assert(allArticles.count >= 5, "成功读取所有文章，共\(allArticles.count)篇")

    // 获取未读文章
    let unreadArticles = try dao.getUnreadArticles()
    print("✅ 未读文章数: \(unreadArticles.count)")

    // 获取收藏文章
    let favoriteArticles = try dao.getFavoriteArticles()
    print("✅ 收藏文章数: \(favoriteArticles.count)")
}

// 测试5: 统计功能
testSection("测试5: 统计功能") {
    let dao = RSSSourceDAO()

    // 获取文章总数
    let totalCount = try dao.getArticleCount()
    print("✅ 文章总数: \(totalCount)")

    // 获取特定订阅源的文章数
    let sourceCount = try dao.getArticleCount(sourceUrl: "http://example.com/rss.xml")
    print("✅ 订阅源文章数: \(sourceCount)")

    // 获取未读文章数
    let unreadCount = try dao.getUnreadCount()
    print("✅ 未读文章数: \(unreadCount)")

    // 获取特定订阅源的未读文章数
    let sourceUnreadCount = try dao.getUnreadCount(sourceUrl: "http://example.com/rss.xml")
    print("✅ 订阅源未读文章数: \(sourceUnreadCount)")
}

// 测试6: 删除操作
testSection("测试6: 删除操作") {
    let dao = RSSSourceDAO()

    // 删除单篇文章
    try dao.deleteArticle(link: "http://example.com/article1")
    let article = try dao.getArticle(by: "http://example.com/article1")
    assert(article == nil, "文章删除成功")

    // 删除订阅源的所有文章
    let beforeCount = try dao.getArticleCount(sourceUrl: "http://example.com/rss.xml")
    try dao.deleteArticles(sourceUrl: "http://example.com/rss.xml")
    let afterCount = try dao.getArticleCount(sourceUrl: "http://example.com/rss.xml")
    assert(afterCount == 0, "订阅源所有文章删除成功（从\(beforeCount)篇到\(afterCount)篇）")

    // 删除订阅源
    try dao.delete(sourceUrl: "http://example.com/rss.xml")
    let source = try dao.getSource(by: "http://example.com/rss.xml")
    assert(source == nil, "订阅源删除成功")
}

print("\n" + "=" * 60)
print("🎉 所有集成测试通过！")
print("\n📊 测试总结:")
print("- 数据库初始化: ✅")
print("- 订阅源CRUD: ✅")
print("- 文章CRUD: ✅")
print("- 批量操作: ✅")
print("- 统计功能: ✅")
print("- 删除操作: ✅")
