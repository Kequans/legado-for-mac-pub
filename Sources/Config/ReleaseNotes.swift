import Foundation

struct ReleaseNote: Identifiable {
    let version: String
    let date: String
    let title: String
    let summary: String
    let changes: [String]

    var id: String { version }
}

enum AppReleaseInfo {
    static let currentVersion = "2.0.0"

    static let notes: [ReleaseNote] = [
        ReleaseNote(
            version: "2.0.0",
            date: "2026-09-19",
            title: "规则兼容与阅读体验升级",
            summary: "补齐 Android Legado 规则语义，提升书源命中率，并优化 macOS 阅读体验。",
            changes: [
                "新增 JSOUP 链式规则、索引区间、排除选择和连接符。",
                "新增递归 JSONPath、常见 XPath、AllInOne、OnlyOne 和模板变量。",
                "支持目录分页、正文分页、Android RSS 字段别名和更多 JavaScript API。",
                "优化阅读器工具栏、封面加载和页面切换动画，减少重复布局与网络请求。",
                "关于页新增版本信息、更新日志和项目支持入口。"
            ]
        ),
        ReleaseNote(
            version: "1.0.0",
            date: "2025-12-30",
            title: "macOS 阅读器基础版",
            summary: "完成书架、书源、在线阅读、本地导入和 RSS 阅读的基础闭环。",
            changes: [
                "支持书架管理、在线搜索、书源导入和章节阅读。",
                "支持 TXT、EPUB、本地缓存、阅读进度和自定义阅读设置。",
                "支持 RSS/Atom 订阅、文章收藏和基础网络配置。"
            ]
        )
    ]
}
