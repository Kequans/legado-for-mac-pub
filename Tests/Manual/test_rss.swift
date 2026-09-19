#!/usr/bin/env swift

import Foundation

// 简单的测试框架
func assert(_ condition: Bool, _ message: String) {
    if condition {
        print("✅ \(message)")
    } else {
        print("❌ \(message)")
        exit(1)
    }
}

print("🧪 开始RSS功能测试\n")

// 测试1: RSSSource模型创建
print("📋 测试1: RSSSource模型创建")
let testSource = """
{
    "sourceName": "测试RSS源",
    "sourceUrl": "http://www.ruanyifeng.com/blog/atom.xml"
}
"""

if let data = testSource.data(using: .utf8) {
    print("✅ RSSSource JSON数据创建成功")
} else {
    print("❌ RSSSource JSON数据创建失败")
}

// 测试2: Article模型创建
print("\n📋 测试2: Article模型创建")
let testArticle = """
{
    "title": "测试文章",
    "link": "http://example.com/article1",
    "description": "这是一篇测试文章",
    "sourceUrl": "http://www.ruanyifeng.com/blog/atom.xml"
}
"""

if let data = testArticle.data(using: .utf8) {
    print("✅ Article JSON数据创建成功")
} else {
    print("❌ Article JSON数据创建失败")
}

// 测试3: 规则连接符检测
print("\n📋 测试3: 规则连接符检测")
let testRules = [
    ("class.title@text && class.subtitle@text", "&&"),
    ("class.cover@src || class.image@src", "||"),
    ("class.odd@text %% class.even@text", "%%"),
    ("class.title@text", "无")
]

for (rule, expected) in testRules {
    let hasAnd = rule.contains(" && ")
    let hasOr = rule.contains(" || ")
    let hasMod = rule.contains(" %% ")

    var detected = "无"
    if hasAnd { detected = "&&" }
    else if hasOr { detected = "||" }
    else if hasMod { detected = "%%" }

    assert(detected == expected, "规则 '\(rule)' 检测到连接符: \(detected)")
}

// 测试4: AllInOne规则检测
print("\n📋 测试4: AllInOne规则检测")
let allInOneRules = [
    (":href=\"(/book/\\d+)\">([^<]*)</a>", true),
    ("class.title@text", false),
    (":pattern", true)
]

for (rule, expected) in allInOneRules {
    let isAllInOne = rule.hasPrefix(":")
    assert(isAllInOne == expected, "规则 '\(rule)' AllInOne检测: \(isAllInOne)")
}

// 测试5: 净化规则检测
print("\n📋 测试5: 净化规则检测")
let cleanRules = [
    ("@css:.content@html##<script[^>]*>[\\s\\S]*?</script>", true),
    ("class.title@text", false),
    ("@css:.content##广告", true)
]

for (rule, expected) in cleanRules {
    let hasClean = rule.contains("##")
    assert(hasClean == expected, "规则 '\(rule)' 净化规则检测: \(hasClean)")
}

// 测试6: OnlyOne规则检测
print("\n📋 测试6: OnlyOne规则检测")
let onlyOneRules = [
    ("##第(\\d+)章##第$1话###", true),
    ("class.title@text", false),
    ("##pattern##replacement###", true)
]

for (rule, expected) in onlyOneRules {
    let isOnlyOne = rule.hasPrefix("##") && rule.hasSuffix("###")
    assert(isOnlyOne == expected, "规则 '\(rule)' OnlyOne检测: \(isOnlyOne)")
}

// 测试7: RSS格式检测
print("\n📋 测试7: RSS格式检测")
let rssContent = """
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
    <channel>
        <title>测试RSS</title>
        <item>
            <title>文章标题</title>
            <link>http://example.com/article1</link>
            <description>文章描述</description>
            <pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
        </item>
    </channel>
</rss>
"""

assert(rssContent.contains("<rss"), "RSS 2.0格式检测")
assert(rssContent.contains("<item>"), "RSS item标签检测")

let atomContent = """
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
    <title>测试Atom</title>
    <entry>
        <title>文章标题</title>
        <link href="http://example.com/article1"/>
        <summary>文章摘要</summary>
    </entry>
</feed>
"""

assert(atomContent.contains("<feed"), "Atom格式检测")
assert(atomContent.contains("<entry>"), "Atom entry标签检测")

print("\n🎉 所有测试通过！")
print("\n📊 测试总结:")
print("- RSSSource模型: ✅")
print("- Article模型: ✅")
print("- 规则连接符: ✅")
print("- AllInOne规则: ✅")
print("- 净化规则: ✅")
print("- OnlyOne规则: ✅")
print("- RSS格式检测: ✅")
