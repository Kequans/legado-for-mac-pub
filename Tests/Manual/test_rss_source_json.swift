import Foundation

// 测试订阅源JSON解析
let jsonString = """
[
  {
    "articleStyle": 0,
    "customOrder": -10100159,
    "enableJs": true,
    "enabled": true,
    "enabledCookieJar": true,
    "jsLib": "test",
    "lastUpdateTime": 0,
    "loadWithBaseUrl": true,
    "loginUi": "test",
    "loginUrl": "test",
    "preload": false,
    "ruleArticles": "@js:test",
    "ruleLink": "$.url",
    "ruleNextPage": "@js:test",
    "rulePubDate": "$.date",
    "ruleTitle": "$.title",
    "showWebLog": false,
    "singleUrl": false,
    "sortUrl": "test",
    "sourceIcon": "data:image/png;base64,test",
    "sourceName": "明月书阁",
    "sourceUrl": "明月书阁",
    "type": 0
  }
]
"""

print("🧪 测试订阅源JSON解析\n")

// 测试1: JSON解码
print("📋 测试1: JSON解码")
if let data = jsonString.data(using: .utf8) {
    do {
        let decoder = JSONDecoder()
        // 注意：这里需要定义RSSSource结构体
        // 由于我们在测试脚本中，无法直接使用项目中的RSSSource
        // 所以我们只测试JSON是否有效
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        if let sources = json {
            print("✅ JSON解析成功，共\(sources.count)个订阅源")

            if let first = sources.first {
                print("\n📊 第一个订阅源的字段:")
                for (key, value) in first {
                    print("  - \(key): \(type(of: value))")
                }

                // 检查关键字段
                print("\n🔍 关键字段检查:")
                print("  sourceName: \(first["sourceName"] as? String ?? "nil")")
                print("  sourceUrl: \(first["sourceUrl"] as? String ?? "nil")")
                print("  enabled: \(first["enabled"] as? Bool ?? false)")
                print("  customOrder: \(first["customOrder"] as? Int ?? 0)")

                // 检查额外字段
                print("\n⚠️ 额外字段（我们的模型中没有）:")
                let extraFields = ["jsLib", "loginUi", "loginUrl", "preload", "ruleNextPage", "showWebLog", "type"]
                for field in extraFields {
                    if first[field] != nil {
                        print("  - \(field): 存在")
                    }
                }
            }
        }
    } catch {
        print("❌ JSON解析失败: \(error)")
    }
} else {
    print("❌ 无法创建Data")
}

// 测试2: 模拟toDatabaseRow
print("\n📋 测试2: 模拟toDatabaseRow")
let testDict: [String: Any?] = [
    "sourceName": "明月书阁",
    "sourceUrl": "明月书阁",  // 注意：这不是一个有效的URL
    "sourceIcon": "data:image/png;base64,test",
    "sourceGroup": nil,
    "enabled": 1,
    "enableJs": 1,
    "enabledCookieJar": 1,
    "customOrder": -10100159,
    "lastUpdateTime": 0,
    "ruleArticles": "@js:test",
    "ruleNextUrl": nil,
    "ruleTitle": "$.title",
    "ruleLink": "$.url",
    "ruleDescription": nil,
    "ruleContent": nil,
    "ruleImage": nil,
    "rulePubDate": "$.date",
    "header": nil,
    "articleStyle": 0,
    "singleUrl": 0,
    "sortUrl": "test",
    "loadWithBaseUrl": 1
]

print("✅ 字典创建成功，共\(testDict.count)个字段")

// 测试3: 检查所有字段是否存在
print("\n📋 测试3: 检查所有必需字段")
let requiredFields = [
    "sourceName", "sourceUrl", "sourceIcon", "sourceGroup",
    "enabled", "enableJs", "enabledCookieJar", "customOrder", "lastUpdateTime",
    "ruleArticles", "ruleNextUrl", "ruleTitle", "ruleLink",
    "ruleDescription", "ruleContent", "ruleImage", "rulePubDate",
    "header", "articleStyle", "singleUrl", "sortUrl", "loadWithBaseUrl"
]

var allFieldsPresent = true
for field in requiredFields {
    if testDict[field] == nil {
        print("❌ 缺少字段: \(field)")
        allFieldsPresent = false
    }
}

if allFieldsPresent {
    print("✅ 所有22个必需字段都存在")
} else {
    print("❌ 有字段缺失")
}

// 测试4: 检查字段值
print("\n📋 测试4: 检查字段值类型")
for (key, value) in testDict {
    if let v = value {
        print("  \(key): \(type(of: v)) = \(v)")
    } else {
        print("  \(key): nil")
    }
}

print("\n🎉 测试完成！")
