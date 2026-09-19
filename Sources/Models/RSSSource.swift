import Foundation

/// 订阅源模型
struct RSSSource: Codable, Identifiable {
    var id: String { sourceUrl }

    // MARK: - 基本信息

    /// 源名称（必填）
    let sourceName: String

    /// 源URL（必填，唯一标识）
    let sourceUrl: String

    /// 图标URL
    var sourceIcon: String?

    /// 源分组
    var sourceGroup: String?

    /// 是否启用
    var enabled: Bool = true

    /// 是否启用JavaScript
    var enableJs: Bool = false

    /// 是否启用Cookie管理
    var enabledCookieJar: Bool = false

    /// 自定义顺序
    var customOrder: Int = 0

    /// 最后更新时间
    var lastUpdateTime: Int64 = 0

    // MARK: - 规则字段

    /// 文章列表规则（为空时使用标准RSS解析）
    var ruleArticles: String?

    /// 列表下一页规则
    var ruleNextUrl: String?

    /// 标题规则（有ruleArticles时必填）
    var ruleTitle: String?

    /// 链接规则（有ruleArticles时必填）
    var ruleLink: String?

    /// 描述规则
    var ruleDescription: String?

    /// 内容规则
    var ruleContent: String?

    /// 图片URL规则
    var ruleImage: String?

    /// 发布时间规则
    var rulePubDate: String?

    // MARK: - 配置字段

    /// 请求头
    var header: String?

    /// 文章样式（0-默认）
    var articleStyle: Int = 0

    /// 是否单URL
    var singleUrl: Bool = false

    /// 排序URL
    var sortUrl: String?

    /// 是否使用baseUrl加载
    var loadWithBaseUrl: Bool = false

    // MARK: - 计算属性

    /// 是否是标准RSS源
    var isStandardRSS: Bool {
        return ruleArticles == nil || ruleArticles?.isEmpty == true
    }

    /// 是否有描述规则
    var hasDescriptionRule: Bool {
        return ruleDescription != nil && !ruleDescription!.isEmpty
    }

    /// 是否有内容规则
    var hasContentRule: Bool {
        return ruleContent != nil && !ruleContent!.isEmpty
    }

    /// 解析后的请求头
    var headerMap: [String: String]? {
        guard let header = header, !header.isEmpty else { return nil }

        // 尝试解析JSON格式的header
        if let data = header.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            return dict
        }

        var result: [String: String] = [:]
        for line in header.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result.isEmpty ? nil : result
    }

    init(
        sourceName: String,
        sourceUrl: String,
        sourceIcon: String? = nil,
        sourceGroup: String? = nil,
        enabled: Bool = true,
        enableJs: Bool = true,
        enabledCookieJar: Bool = true,
        customOrder: Int = 0,
        lastUpdateTime: Int64 = 0,
        ruleArticles: String? = nil,
        ruleNextUrl: String? = nil,
        ruleTitle: String? = nil,
        ruleLink: String? = nil,
        ruleDescription: String? = nil,
        ruleContent: String? = nil,
        ruleImage: String? = nil,
        rulePubDate: String? = nil,
        header: String? = nil,
        articleStyle: Int = 0,
        singleUrl: Bool = false,
        sortUrl: String? = nil,
        loadWithBaseUrl: Bool = true
    ) {
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.sourceIcon = sourceIcon
        self.sourceGroup = sourceGroup
        self.enabled = enabled
        self.enableJs = enableJs
        self.enabledCookieJar = enabledCookieJar
        self.customOrder = customOrder
        self.lastUpdateTime = lastUpdateTime
        self.ruleArticles = ruleArticles
        self.ruleNextUrl = ruleNextUrl
        self.ruleTitle = ruleTitle
        self.ruleLink = ruleLink
        self.ruleDescription = ruleDescription
        self.ruleContent = ruleContent
        self.ruleImage = ruleImage
        self.rulePubDate = rulePubDate
        self.header = header
        self.articleStyle = articleStyle
        self.singleUrl = singleUrl
        self.sortUrl = sortUrl
        self.loadWithBaseUrl = loadWithBaseUrl
    }

    // MARK: - 编码键

    enum CodingKeys: String, CodingKey {
        case sourceName
        case sourceUrl
        case sourceIcon
        case sourceGroup
        case enabled
        case enableJs
        case enabledCookieJar
        case customOrder
        case lastUpdateTime
        case ruleArticles
        case ruleNextUrl
        case ruleTitle
        case ruleLink
        case ruleDescription
        case ruleContent
        case ruleImage
        case rulePubDate
        case header
        case articleStyle
        case singleUrl
        case sortUrl
        case loadWithBaseUrl
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case ruleNextPage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
        sourceIcon = try container.decodeIfPresent(String.self, forKey: .sourceIcon)
        sourceGroup = try container.decodeIfPresent(String.self, forKey: .sourceGroup)
        enabled = Self.decodeBool(container, key: .enabled) ?? true
        enableJs = Self.decodeBool(container, key: .enableJs) ?? true
        enabledCookieJar = Self.decodeBool(container, key: .enabledCookieJar) ?? true
        customOrder = Self.decodeInt(container, key: .customOrder) ?? 0
        lastUpdateTime = Self.decodeInt64(container, key: .lastUpdateTime) ?? 0
        ruleArticles = try container.decodeIfPresent(String.self, forKey: .ruleArticles)
        ruleNextUrl = try container.decodeIfPresent(String.self, forKey: .ruleNextUrl)
            ?? (try decoder.container(keyedBy: LegacyCodingKeys.self).decodeIfPresent(String.self, forKey: .ruleNextPage))
        ruleTitle = try container.decodeIfPresent(String.self, forKey: .ruleTitle)
        ruleLink = try container.decodeIfPresent(String.self, forKey: .ruleLink)
        ruleDescription = try container.decodeIfPresent(String.self, forKey: .ruleDescription)
        ruleContent = try container.decodeIfPresent(String.self, forKey: .ruleContent)
        ruleImage = try container.decodeIfPresent(String.self, forKey: .ruleImage)
        rulePubDate = try container.decodeIfPresent(String.self, forKey: .rulePubDate)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        articleStyle = Self.decodeInt(container, key: .articleStyle) ?? 0
        singleUrl = Self.decodeBool(container, key: .singleUrl) ?? false
        sortUrl = try container.decodeIfPresent(String.self, forKey: .sortUrl)
        loadWithBaseUrl = Self.decodeBool(container, key: .loadWithBaseUrl) ?? true
    }

    private static func decodeBool(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Bool? {
        if let value = try? container.decode(Bool.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    private static func decodeInt64(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key) { return Int64(value) }
        return nil
    }
}

/// 文章模型
struct Article: Identifiable, Codable {
    var id: String { link }

    /// 标题
    let title: String

    /// 链接（唯一标识）
    let link: String

    /// 描述/摘要
    var description: String?

    /// 完整内容
    var content: String?

    /// 图片URL
    var imageUrl: String?

    /// 发布时间
    var pubDate: Date?

    /// 所属订阅源URL
    var sourceUrl: String

    /// 是否已读
    var isRead: Bool = false

    /// 是否收藏
    var isFavorite: Bool = false

    /// 阅读时间
    var readTime: Date?

    // MARK: - 编码键

    enum CodingKeys: String, CodingKey {
        case title
        case link
        case description
        case content
        case imageUrl
        case pubDate
        case sourceUrl
        case isRead
        case isFavorite
        case readTime
    }
}

// MARK: - 扩展：数据库支持

import GRDB

extension RSSSource {
    /// 从GRDB Row创建
    init?(from row: Row) {
        // 必填字段
        guard let sourceName: String = row["sourceName"],
              let sourceUrl: String = row["sourceUrl"],
              !sourceName.isEmpty,
              !sourceUrl.isEmpty else {
            print("❌ [RSSSource] 缺少必填字段: sourceName或sourceUrl")
            return nil
        }

        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.sourceIcon = row["sourceIcon"]
        self.sourceGroup = row["sourceGroup"]
        self.enabled = (row["enabled"] as Int? ?? 1) != 0
        self.enableJs = (row["enableJs"] as Int? ?? 0) != 0
        self.enabledCookieJar = (row["enabledCookieJar"] as Int? ?? 0) != 0
        self.customOrder = row["customOrder"] ?? 0
        self.lastUpdateTime = row["lastUpdateTime"] ?? 0

        self.ruleArticles = row["ruleArticles"]
        self.ruleNextUrl = row["ruleNextUrl"]
        self.ruleTitle = row["ruleTitle"]
        self.ruleLink = row["ruleLink"]
        self.ruleDescription = row["ruleDescription"]
        self.ruleContent = row["ruleContent"]
        self.ruleImage = row["ruleImage"]
        self.rulePubDate = row["rulePubDate"]

        self.header = row["header"]
        self.articleStyle = row["articleStyle"] ?? 0
        self.singleUrl = (row["singleUrl"] as Int? ?? 0) != 0
        self.sortUrl = row["sortUrl"]
        self.loadWithBaseUrl = (row["loadWithBaseUrl"] as Int? ?? 0) != 0
    }

    /// 转换为数据库行
    func toDatabaseRow() -> [String: Any?] {
        return [
            "sourceName": sourceName,
            "sourceUrl": sourceUrl,
            "sourceIcon": sourceIcon,
            "sourceGroup": sourceGroup,
            "enabled": enabled ? 1 : 0,
            "enableJs": enableJs ? 1 : 0,
            "enabledCookieJar": enabledCookieJar ? 1 : 0,
            "customOrder": customOrder,
            "lastUpdateTime": Int64(lastUpdateTime),  // 确保是Int64
            "ruleArticles": ruleArticles,
            "ruleNextUrl": ruleNextUrl,
            "ruleTitle": ruleTitle,
            "ruleLink": ruleLink,
            "ruleDescription": ruleDescription,
            "ruleContent": ruleContent,
            "ruleImage": ruleImage,
            "rulePubDate": rulePubDate,
            "header": header,
            "articleStyle": articleStyle,
            "singleUrl": singleUrl ? 1 : 0,
            "sortUrl": sortUrl,
            "loadWithBaseUrl": loadWithBaseUrl ? 1 : 0
        ]
    }
}

extension Article {
    /// 从GRDB Row创建
    init?(from row: Row) {
        // 必填字段
        guard let title: String = row["title"],
              let link: String = row["link"],
              let sourceUrl: String = row["sourceUrl"],
              !title.isEmpty,
              !link.isEmpty,
              !sourceUrl.isEmpty else {
            return nil
        }

        self.title = title
        self.link = link
        self.sourceUrl = sourceUrl
        self.description = row["description"]
        self.content = row["content"]
        self.imageUrl = row["imageUrl"]
        self.isRead = (row["isRead"] as Int? ?? 0) != 0
        self.isFavorite = (row["isFavorite"] as Int? ?? 0) != 0

        if let timestamp: Int64 = row["pubDate"] {
            self.pubDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }

        if let timestamp: Int64 = row["readTime"] {
            self.readTime = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
    }

    /// 转换为数据库行
    func toDatabaseRow() -> [String: Any?] {
        return [
            "title": title,
            "link": link,
            "sourceUrl": sourceUrl,
            "description": description,
            "content": content,
            "imageUrl": imageUrl,
            "pubDate": pubDate.map { Int64($0.timeIntervalSince1970) },
            "isRead": isRead ? 1 : 0,
            "isFavorite": isFavorite ? 1 : 0,
            "readTime": readTime.map { Int64($0.timeIntervalSince1970) }
        ]
    }
}
