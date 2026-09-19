import Foundation
import SwiftUI

/// 订阅源管理ViewModel
@MainActor
class RSSSourceViewModel: ObservableObject {
    @Published var sources: [RSSSource] = []
    @Published var selectedSource: RSSSource?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let dao = RSSSourceDAO()
    private let engine = RSSSourceEngine()

    // MARK: - 初始化

    init() {
        loadSources()
    }

    // MARK: - 数据加载

    /// 加载所有订阅源
    func loadSources() {
        isLoading = true
        errorMessage = nil

        do {
            sources = try dao.getAllSources()
            print("📰 加载了 \(sources.count) 个订阅源")
        } catch {
            errorMessage = "加载订阅源失败: \(error.localizedDescription)"
            print("❌ \(errorMessage ?? "")")
        }

        isLoading = false
    }

    /// 刷新订阅源
    func refreshSource(_ source: RSSSource) async {
        isLoading = true
        errorMessage = nil

        do {
            // 解析订阅源
            let articles = try await engine.parse(source: source)
            print("📰 从【\(source.sourceName)】获取到 \(articles.count) 篇文章")

            // 保存文章到数据库
            try dao.saveAll(articles)

            // 更新最后更新时间
            let now = Int64(Date().timeIntervalSince1970)
            try dao.updateLastUpdateTime(sourceUrl: source.sourceUrl, time: now)

            // 重新加载
            loadSources()
        } catch {
            errorMessage = "刷新失败: \(error.localizedDescription)"
            print("❌ \(errorMessage ?? "")")
        }

        isLoading = false
    }

    /// 刷新所有启用的订阅源
    func refreshAllSources() async {
        isLoading = true
        errorMessage = nil

        do {
            let enabledSources = try dao.getEnabledSources()
            print("📰 开始刷新 \(enabledSources.count) 个订阅源")

            for source in enabledSources {
                do {
                    let articles = try await engine.parse(source: source)
                    try dao.saveAll(articles)

                    let now = Int64(Date().timeIntervalSince1970)
                    try dao.updateLastUpdateTime(sourceUrl: source.sourceUrl, time: now)

                    print("✅ 【\(source.sourceName)】刷新成功，获取 \(articles.count) 篇文章")
                } catch {
                    print("❌ 【\(source.sourceName)】刷新失败: \(error.localizedDescription)")
                }
            }

            loadSources()
        } catch {
            errorMessage = "刷新失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - 订阅源操作

    /// 添加订阅源
    func addSource(_ source: RSSSource) {
        print("📝 准备添加订阅源: \(source.sourceName)")
        do {
            try dao.save(source)
            print("✅ 订阅源保存成功")
            loadSources()
            print("📰 重新加载后有 \(sources.count) 个订阅源")
        } catch {
            print("❌ 添加订阅源失败: \(error)")
            errorMessage = "添加订阅源失败: \(error.localizedDescription)"
        }
    }

    /// 删除订阅源
    func deleteSource(_ source: RSSSource) {
        do {
            try dao.delete(sourceUrl: source.sourceUrl)
            try dao.deleteArticles(sourceUrl: source.sourceUrl)
            loadSources()
        } catch {
            errorMessage = "删除订阅源失败: \(error.localizedDescription)"
        }
    }

    /// 切换启用状态
    func toggleEnabled(_ source: RSSSource) {
        do {
            try dao.updateEnabled(sourceUrl: source.sourceUrl, enabled: !source.enabled)
            loadSources()
        } catch {
            errorMessage = "更新状态失败: \(error.localizedDescription)"
        }
    }

    /// 导入订阅源
    func importSources(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()

            // 尝试解析为数组
            if let sources = try? decoder.decode([RSSSource].self, from: data) {
                try dao.saveAll(sources)
                loadSources()
                print("✅ 导入了 \(sources.count) 个订阅源")
            }
            // 尝试解析为单个对象
            else if let source = try? decoder.decode(RSSSource.self, from: data) {
                try dao.save(source)
                loadSources()
                print("✅ 导入了 1 个订阅源")
            }
            else {
                errorMessage = "无效的订阅源文件格式"
            }
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
        }
    }

    /// 从URL导入订阅源
    func importFromUrl(_ urlString: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try await NetworkManager.shared.get(url: urlString)
            guard let data = content.data(using: .utf8) else {
                errorMessage = "无法解析数据"
                isLoading = false
                return
            }

            let decoder = JSONDecoder()

            // 尝试解析为数组
            if let sources = try? decoder.decode([RSSSource].self, from: data) {
                try dao.saveAll(sources)
                loadSources()
                print("✅ 从URL导入了 \(sources.count) 个订阅源")
            }
            // 尝试解析为单个对象
            else if let source = try? decoder.decode(RSSSource.self, from: data) {
                try dao.save(source)
                loadSources()
                print("✅ 从URL导入了 1 个订阅源")
            }
            else {
                errorMessage = "无效的订阅源格式"
            }
        } catch {
            errorMessage = "导入失败: \(error.localizedDescription)"
            print("❌ 从URL导入失败: \(error)")
        }

        isLoading = false
    }

    /// 导出订阅源
    func exportSources(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sources)
            try data.write(to: url)
            print("✅ 导出了 \(sources.count) 个订阅源")
        } catch {
            errorMessage = "导出失败: \(error.localizedDescription)"
        }
    }
}

/// 文章列表ViewModel
@MainActor
class ArticleListViewModel: ObservableObject {
    @Published var articles: [Article] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var unreadCount = 0

    private let dao = RSSSourceDAO()
    private let engine = RSSSourceEngine()

    var source: RSSSource?

    // MARK: - 初始化

    init(source: RSSSource? = nil) {
        self.source = source
        loadArticles()
    }

    // MARK: - 数据加载

    /// 加载文章列表
    func loadArticles() {
        isLoading = true
        errorMessage = nil

        do {
            if let source = source {
                // 加载特定订阅源的文章
                articles = try dao.getArticles(sourceUrl: source.sourceUrl)
                unreadCount = try dao.getUnreadCount(sourceUrl: source.sourceUrl)
            } else {
                // 加载所有文章
                articles = try dao.getAllArticles()
                unreadCount = try dao.getUnreadCount()
            }
            print("📰 加载了 \(articles.count) 篇文章，未读 \(unreadCount) 篇")
        } catch {
            errorMessage = "加载文章失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 加载未读文章
    func loadUnreadArticles() {
        isLoading = true
        errorMessage = nil

        do {
            articles = try dao.getUnreadArticles()
            unreadCount = articles.count
            print("📰 加载了 \(articles.count) 篇未读文章")
        } catch {
            errorMessage = "加载未读文章失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// 加载收藏文章
    func loadFavoriteArticles() {
        isLoading = true
        errorMessage = nil

        do {
            articles = try dao.getFavoriteArticles()
            print("📰 加载了 \(articles.count) 篇收藏文章")
        } catch {
            errorMessage = "加载收藏文章失败: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - 文章操作

    /// 标记为已读
    func markAsRead(_ article: Article) {
        do {
            try dao.markAsRead(link: article.link)
            loadArticles()
        } catch {
            errorMessage = "标记失败: \(error.localizedDescription)"
        }
    }

    /// 标记为未读
    func markAsUnread(_ article: Article) {
        do {
            try dao.markAsUnread(link: article.link)
            loadArticles()
        } catch {
            errorMessage = "标记失败: \(error.localizedDescription)"
        }
    }

    /// 切换收藏状态
    func toggleFavorite(_ article: Article) {
        do {
            try dao.toggleFavorite(link: article.link)
            loadArticles()
        } catch {
            errorMessage = "收藏失败: \(error.localizedDescription)"
        }
    }

    /// 获取文章内容
    func fetchContent(for article: Article) async -> String? {
        guard let source = source, source.hasContentRule else {
            return nil
        }

        do {
            let content = try await engine.fetchArticleContent(article: article, source: source)
            try dao.updateContent(link: article.link, content: content)
            return content
        } catch {
            errorMessage = "获取内容失败: \(error.localizedDescription)"
            return nil
        }
    }
}
