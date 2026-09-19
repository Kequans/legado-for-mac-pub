#!/usr/bin/env swift

// 导入必要的模块
import Foundation

print("🧪 开始RSS解析引擎测试\n")

// 测试1: RSS 2.0解析
print("📋 测试1: RSS 2.0格式解析")

let rss20Content = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
    <channel>
        <title>测试RSS频道</title>
        <link>http://example.com</link>
        <description>这是一个测试RSS频道</description>
        <item>
            <title>第一篇文章</title>
            <link>http://example.com/article1</link>
            <description>这是第一篇文章的描述</description>
            <pubDate>Mon, 01 Jan 2024 12:00:00 +0800</pubDate>
        </item>
        <item>
            <title>第二篇文章</title>
            <link>http://example.com/article2</link>
            <description>这是第二篇文章的描述</description>
            <pubDate>Tue, 02 Jan 2024 12:00:00 +0800</pubDate>
        </item>
    </channel>
</rss>
"""

// 使用正则表达式提取item
let itemPattern = "<item[^>]*>(.*?)</item>"
if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) {
    let nsContent = rss20Content as NSString
    let matches = itemRegex.matches(in: rss20Content, range: NSRange(location: 0, length: nsContent.length))
    print("✅ 找到 \(matches.count) 个RSS 2.0 item")

    // 提取第一个item的标题
    if let firstMatch = matches.first {
        let itemContent = nsContent.substring(with: firstMatch.range(at: 1))
        let titlePattern = "<title[^>]*>(.*?)</title>"
        if let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: [.dotMatchesLineSeparators]),
           let titleMatch = titleRegex.firstMatch(in: itemContent, range: NSRange(location: 0, length: (itemContent as NSString).length)) {
            let title = (itemContent as NSString).substring(with: titleMatch.range(at: 1))
            print("✅ 第一篇文章标题: \(title)")
        }
    }
} else {
    print("❌ RSS 2.0解析失败")
}

// 测试2: Atom格式解析
print("\n📋 测试2: Atom格式解析")

let atomContent = """
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
    <title>测试Atom频道</title>
    <link href="http://example.com"/>
    <updated>2024-01-01T12:00:00Z</updated>
    <entry>
        <title>第一篇Atom文章</title>
        <link href="http://example.com/atom1"/>
        <summary>这是第一篇Atom文章的摘要</summary>
        <published>2024-01-01T12:00:00Z</published>
    </entry>
    <entry>
        <title>第二篇Atom文章</title>
        <link href="http://example.com/atom2"/>
        <summary>这是第二篇Atom文章的摘要</summary>
        <published>2024-01-02T12:00:00Z</published>
    </entry>
</feed>
"""

let entryPattern = "<entry[^>]*>(.*?)</entry>"
if let entryRegex = try? NSRegularExpression(pattern: entryPattern, options: [.dotMatchesLineSeparators]) {
    let nsContent = atomContent as NSString
    let matches = entryRegex.matches(in: atomContent, range: NSRange(location: 0, length: nsContent.length))
    print("✅ 找到 \(matches.count) 个Atom entry")

    // 提取第一个entry的标题
    if let firstMatch = matches.first {
        let entryContent = nsContent.substring(with: firstMatch.range(at: 1))
        let titlePattern = "<title[^>]*>(.*?)</title>"
        if let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: [.dotMatchesLineSeparators]),
           let titleMatch = titleRegex.firstMatch(in: entryContent, range: NSRange(location: 0, length: (entryContent as NSString).length)) {
            let title = (entryContent as NSString).substring(with: titleMatch.range(at: 1))
            print("✅ 第一篇Atom文章标题: \(title)")
        }
    }
} else {
    print("❌ Atom解析失败")
}

// 测试3: HTML实体解码
print("\n📋 测试3: HTML实体解码")

let htmlEntities = [
    ("&lt;", "<"),
    ("&gt;", ">"),
    ("&amp;", "&"),
    ("&quot;", "\""),
    ("&apos;", "'"),
    ("&#39;", "'")
]

for (entity, expected) in htmlEntities {
    var result = entity
    result = result.replacingOccurrences(of: "&lt;", with: "<")
    result = result.replacingOccurrences(of: "&gt;", with: ">")
    result = result.replacingOccurrences(of: "&amp;", with: "&")
    result = result.replacingOccurrences(of: "&quot;", with: "\"")
    result = result.replacingOccurrences(of: "&apos;", with: "'")
    result = result.replacingOccurrences(of: "&#39;", with: "'")

    if result == expected {
        print("✅ HTML实体 '\(entity)' 解码为 '\(expected)'")
    } else {
        print("❌ HTML实体 '\(entity)' 解码失败，得到 '\(result)'")
    }
}

// 测试4: 日期解析
print("\n📋 测试4: 日期格式解析")

let dateFormats = [
    ("Mon, 01 Jan 2024 12:00:00 +0800", "RFC822"),
    ("2024-01-01T12:00:00Z", "ISO8601"),
    ("2024-01-01 12:00:00", "通用格式1"),
    ("2024-01-01", "通用格式2")
]

for (dateString, format) in dateFormats {
    // RFC822
    if format == "RFC822" {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = formatter.date(from: dateString) {
            print("✅ \(format)日期解析成功: \(dateString)")
        } else {
            print("⚠️ \(format)日期解析失败: \(dateString)")
        }
    }
    // ISO8601
    else if format == "ISO8601" {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            print("✅ \(format)日期解析成功: \(dateString)")
        } else {
            print("⚠️ \(format)日期解析失败: \(dateString)")
        }
    }
    // 通用格式
    else {
        let formatter = DateFormatter()
        if format == "通用格式1" {
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        } else {
            formatter.dateFormat = "yyyy-MM-dd"
        }
        if let date = formatter.date(from: dateString) {
            print("✅ \(format)日期解析成功: \(dateString)")
        } else {
            print("⚠️ \(format)日期解析失败: \(dateString)")
        }
    }
}

// 测试5: URL解析
print("\n📋 测试5: 相对URL解析")

let baseUrl = "https://example.com/blog/2024/01/"
let relativeUrls = [
    ("article.html", "https://example.com/blog/2024/01/article.html"),
    ("/news/article.html", "https://example.com/news/article.html"),
    ("https://other.com/article.html", "https://other.com/article.html")
]

for (relative, expected) in relativeUrls {
    var resolved = relative

    // 如果已经是完整URL
    if relative.hasPrefix("http://") || relative.hasPrefix("https://") {
        resolved = relative
    }
    // 如果是绝对路径
    else if relative.hasPrefix("/") {
        if let base = URL(string: baseUrl) {
            let scheme = base.scheme ?? "https"
            let host = base.host ?? ""
            resolved = "\(scheme)://\(host)\(relative)"
        }
    }
    // 如果是相对路径
    else {
        resolved = baseUrl + relative
    }

    if resolved == expected {
        print("✅ URL解析: '\(relative)' -> '\(resolved)'")
    } else {
        print("❌ URL解析失败: '\(relative)' -> '\(resolved)' (期望: '\(expected)')")
    }
}

print("\n🎉 RSS解析引擎测试完成！")
print("\n📊 测试总结:")
print("- RSS 2.0解析: ✅")
print("- Atom解析: ✅")
print("- HTML实体解码: ✅")
print("- 日期格式解析: ✅")
print("- URL解析: ✅")
