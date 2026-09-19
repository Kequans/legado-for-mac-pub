import Foundation

/// 书源模型
struct BookSource: Identifiable, Codable, Hashable {
    var id: String { bookSourceUrl }
    
    // 基本信息
    var bookSourceUrl: String              // 书源地址
    var bookSourceName: String             // 书源名称
    var bookSourceGroup: String?           // 分组
    var bookSourceType: Int = 0            // 类型: 0-文本, 1-音频, 2-图片, 3-文件
    var bookUrlPattern: String?            // 详情页URL正则
    var customOrder: Int = 0               // 排序
    var enabled: Bool = true               // 是否启用
    var enabledExplore: Bool = true        // 启用发现
    
    // 网络配置
    var header: String?                    // 请求头
    var loginUrl: String?                  // 登录地址
    var loginUi: String?                   // 登录UI
    var loginCheckJs: String?              // 登录检测JS
    var coverDecodeJs: String?             // 封面解密JS
    var concurrentRate: String?            // 并发率
    var enabledCookieJar: Bool = true      // 启用Cookie Jar
    
    // JS库和注释
    var jsLib: String?                     // JS库
    var bookSourceComment: String?         // 注释
    var variableComment: String?           // 变量说明
    
    // 时间和权重
    var lastUpdateTime: Int64 = 0          // 最后更新时间
    var respondTime: Int64 = 180000        // 响应时间
    var weight: Int = 0                    // 权重
    
    // 发现规则
    var exploreUrl: String?                // 发现URL
    var exploreScreen: String?             // 发现筛选规则
    var ruleExplore: ExploreRule?          // 发现规则
    
    // 搜索规则
    var searchUrl: String?                 // 搜索URL
    var ruleSearch: SearchRule?            // 搜索规则
    
    // 书籍规则
    var ruleBookInfo: BookInfoRule?        // 书籍信息规则
    var ruleToc: TocRule?                  // 目录规则
    var ruleContent: ContentRule?          // 正文规则
    var ruleReview: ReviewRule?            // 评论规则
    
    init(bookSourceUrl: String, bookSourceName: String) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.lastUpdateTime = Int64(Date().timeIntervalSince1970)
    }
    
    // 自定义解码器,处理ruleExplore可能是空数组的情况
    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType
        case bookUrlPattern, customOrder, enabled, enabledExplore
        case header, loginUrl, loginUi, loginCheckJs, coverDecodeJs
        case concurrentRate, enabledCookieJar, jsLib, bookSourceComment
        case variableComment, lastUpdateTime, respondTime, weight
        case exploreUrl, exploreScreen, ruleExplore
        case searchUrl, ruleSearch
        case ruleBookInfo, ruleToc, ruleContent, ruleReview
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        bookSourceUrl = try container.decode(String.self, forKey: .bookSourceUrl)
        bookSourceName = try container.decode(String.self, forKey: .bookSourceName)
        bookSourceGroup = try container.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceType = try container.decodeIfPresent(Int.self, forKey: .bookSourceType) ?? 0
        bookUrlPattern = try container.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        customOrder = try container.decodeIfPresent(Int.self, forKey: .customOrder) ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        enabledExplore = try container.decodeIfPresent(Bool.self, forKey: .enabledExplore) ?? true
        
        header = try container.decodeIfPresent(String.self, forKey: .header)
        loginUrl = try container.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi = try container.decodeIfPresent(String.self, forKey: .loginUi)
        loginCheckJs = try container.decodeIfPresent(String.self, forKey: .loginCheckJs)
        coverDecodeJs = try container.decodeIfPresent(String.self, forKey: .coverDecodeJs)
        concurrentRate = try container.decodeIfPresent(String.self, forKey: .concurrentRate)
        enabledCookieJar = try container.decodeIfPresent(Bool.self, forKey: .enabledCookieJar) ?? true
        
        jsLib = try container.decodeIfPresent(String.self, forKey: .jsLib)
        bookSourceComment = try container.decodeIfPresent(String.self, forKey: .bookSourceComment)
        variableComment = try container.decodeIfPresent(String.self, forKey: .variableComment)
        
        // 处理lastUpdateTime: 可能是字符串或Int64
        if let timeInt = try? container.decode(Int64.self, forKey: .lastUpdateTime) {
            lastUpdateTime = timeInt
        } else if let timeStr = try? container.decode(String.self, forKey: .lastUpdateTime),
                  let timeInt = Int64(timeStr) {
            lastUpdateTime = timeInt
        } else {
            lastUpdateTime = 0
        }
        
        // 处理respondTime: 可能是字符串或Int64
        if let timeInt = try? container.decode(Int64.self, forKey: .respondTime) {
            respondTime = timeInt
        } else if let timeStr = try? container.decode(String.self, forKey: .respondTime),
                  let timeInt = Int64(timeStr) {
            respondTime = timeInt
        } else {
            respondTime = 180000
        }
        
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        
        exploreUrl = try container.decodeIfPresent(String.self, forKey: .exploreUrl)
        exploreScreen = try container.decodeIfPresent(String.self, forKey: .exploreScreen)
        
        // 处理ruleExplore: 可能是对象或空数组
        if let explore = try? container.decode(ExploreRule.self, forKey: .ruleExplore) {
            ruleExplore = explore
        } else if let _ = try? container.decode([String].self, forKey: .ruleExplore) {
            // 如果是空数组,设置为nil
            ruleExplore = nil
        } else {
            ruleExplore = nil
        }
        
        searchUrl = try container.decodeIfPresent(String.self, forKey: .searchUrl)

        // 处理ruleSearch: 可能是对象或空对象
        if let search = try? container.decode(SearchRule.self, forKey: .ruleSearch) {
            ruleSearch = search
        } else {
            ruleSearch = nil
        }

        // 处理ruleBookInfo: 可能是对象或空对象
        if let bookInfo = try? container.decode(BookInfoRule.self, forKey: .ruleBookInfo) {
            ruleBookInfo = bookInfo
        } else {
            ruleBookInfo = nil
        }

        // 处理ruleToc: 可能是对象或空对象
        if let toc = try? container.decode(TocRule.self, forKey: .ruleToc) {
            ruleToc = toc
        } else {
            ruleToc = nil
        }

        // 处理ruleContent: 可能是对象或空对象
        if let content = try? container.decode(ContentRule.self, forKey: .ruleContent) {
            ruleContent = content
        } else {
            ruleContent = nil
        }

        // 处理ruleReview: 可能是对象或空对象
        if let review = try? container.decode(ReviewRule.self, forKey: .ruleReview) {
            ruleReview = review
        } else {
            ruleReview = nil
        }
    }
}

// MARK: - 规则结构

/// 搜索规则
struct SearchRule: Codable, Hashable {
    var checkKeyWord: String?               // 校验关键字
    var bookList: String?                  // 书籍列表规则
    var name: String?                      // 书名规则
    var author: String?                    // 作者规则
    var kind: String?                      // 分类规则
    var intro: String?                     // 简介规则
    var coverUrl: String?                  // 封面规则
    var bookUrl: String?                   // 详情页规则
    var wordCount: String?                 // 字数规则
    var lastChapter: String?               // 最新章节规则
    var updateTime: String?                // 更新时间规则
}

/// 发现规则
struct ExploreRule: Codable, Hashable {
    var bookList: String?
    var name: String?
    var author: String?
    var kind: String?
    var intro: String?
    var coverUrl: String?
    var bookUrl: String?
    var wordCount: String?
    var lastChapter: String?
    var updateTime: String?
}

/// 书籍信息规则
struct BookInfoRule: Codable, Hashable {
    var `init`: String?                    // 预处理规则
    var name: String?                      // 书名规则
    var author: String?                    // 作者规则
    var intro: String?                     // 简介规则
    var kind: String?                      // 分类规则
    var coverUrl: String?                  // 封面规则
    var tocUrl: String?                    // 目录页规则
    var wordCount: String?                 // 字数规则
    var lastChapter: String?               // 最新章节规则
    var updateTime: String?                // 更新时间规则
    var canReName: String?                 // 能否改名规则
    var downloadUrls: String?              // 下载地址规则
}

/// 目录规则
struct TocRule: Codable, Hashable {
    var preUpdateJs: String?               // 更新目录前执行的 JS
    var chapterList: String?               // 章节列表规则
    var chapterName: String?               // 章节名规则
    var chapterUrl: String?                // 章节URL规则
    var isVolume: String?                  // 是否卷名规则
    var updateTime: String?                // 更新时间规则
    var isVip: String?                     // 是否VIP规则
    var isPay: String?                     // 是否付费规则
    var nextTocUrl: String?                // 下一页目录规则
    var formatJs: String?                  // 目录格式化 JS
}

/// 正文规则
struct ContentRule: Codable, Hashable {
    var content: String?                   // 正文规则
    var title: String?                     // 正文标题规则
    var nextContentUrl: String?            // 下一页正文规则
    var webJs: String?                     // WebView JS
    var sourceRegex: String?               // 源码正则
    var replaceRegex: String?              // 替换正则
    var imageStyle: String?                // 图片样式
    var imageDecode: String?               // 图片解密
    var payAction: String?                 // 付费操作
}

/// 评论规则
struct ReviewRule: Codable, Hashable {
    var reviewUrl: String?                 // 评论URL
    var avatarRule: String?                // 头像规则
    var contentRule: String?               // 内容规则
    var postTimeRule: String?              // 发布时间规则
    var reviewQuoteUrl: String?            // 引用URL规则
}

extension BookSource {
    static let example = BookSource(
        bookSourceUrl: "https://example.com",
        bookSourceName: "示例书源"
    )
}
