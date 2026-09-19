import Foundation

/// 规则连接符号处理器
class RuleConnector {
    /// 连接符号类型
    enum ConnectorType {
        case and    // && - 合并所有取到的值
        case or     // || - 以第一个取到值的为准
        case mod    // %% - 依次取数（轮流从多个列表中取值）
    }

    /// 检测规则中的连接符号
    static func detectConnector(in rule: String) -> ConnectorType? {
        if rule.contains("&&") {
            return .and
        } else if rule.contains("||") {
            return .or
        } else if rule.contains("%%") {
            return .mod
        }
        return nil
    }

    /// 分割规则（按连接符号）
    static func splitRule(_ rule: String, by connector: ConnectorType) -> [String] {
        let separator: String
        switch connector {
        case .and:
            separator = "&&"
        case .or:
            separator = "||"
        case .mod:
            separator = "%%"
        }

        return rule.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 合并结果（根据连接符号类型）
    static func mergeResults(_ results: [[Any]], connector: ConnectorType) -> [Any] {
        switch connector {
        case .and:
            // && - 合并所有取到的值
            return mergeAnd(results)
        case .or:
            // || - 以第一个取到值的为准
            return mergeOr(results)
        case .mod:
            // %% - 依次取数（轮流从多个列表中取值）
            return mergeMod(results)
        }
    }

    /// && 合并：合并所有取到的值
    private static func mergeAnd(_ results: [[Any]]) -> [Any] {
        var merged: [Any] = []

        for result in results {
            merged.append(contentsOf: result)
        }

        return merged
    }

    /// || 合并：以第一个取到值的为准
    private static func mergeOr(_ results: [[Any]]) -> [Any] {
        for result in results {
            if !result.isEmpty {
                return result
            }
        }
        return []
    }

    /// %% 合并：依次取数（轮流从多个列表中取值）
    private static func mergeMod(_ results: [[Any]]) -> [Any] {
        var merged: [Any] = []
        var maxLength = 0

        // 找出最长的列表
        for result in results {
            maxLength = max(maxLength, result.count)
        }

        // 轮流取值
        for i in 0..<maxLength {
            for result in results {
                if i < result.count {
                    merged.append(result[i])
                }
            }
        }

        return merged
    }
}

/// 正则AllInOne规则处理器
class RegexAllInOneParser {
    /// 检测是否是AllInOne规则（以:开头）
    static func isAllInOneRule(_ rule: String) -> Bool {
        return rule.hasPrefix(":")
    }

    /// 解析AllInOne规则
    /// - Parameters:
    ///   - rule: 规则字符串（如 `:href="(/chapter/[^"]*)">([^<]*)</a>`）
    ///   - content: 要解析的内容
    /// - Returns: 解析结果数组，每个元素是一个字典，包含捕获组
    static func parse(rule: String, content: String) throws -> [[String: String]] {
        // 移除开头的 :
        let pattern = String(rule.dropFirst())

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw RegexError.invalidPattern(pattern)
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        var results: [[String: String]] = []

        for match in matches {
            var dict: [String: String] = [:]

            // 捕获组从1开始（0是整个匹配）
            for i in 1..<match.numberOfRanges {
                let range = match.range(at: i)
                if range.location != NSNotFound {
                    let value = nsContent.substring(with: range)
                    dict["$\(i)"] = value
                }
            }

            if !dict.isEmpty {
                results.append(dict)
            }
        }

        return results
    }

    /// 从AllInOne结果中提取指定字段
    /// - Parameters:
    ///   - results: AllInOne解析结果
    ///   - field: 字段名（如 "$1", "$2"）
    /// - Returns: 提取的值数组
    static func extractField(from results: [[String: String]], field: String) -> [String] {
        return results.compactMap { $0[field] }
    }
}

/// 正则净化处理器
class RegexCleaner {
    /// 检测规则中的正则净化（##pattern##replacement）
    static func hasCleanRule(in rule: String) -> Bool {
        return rule.contains("##")
    }

    /// 提取规则和净化表达式
    /// - Parameter rule: 完整规则
    /// - Returns: (主规则, 净化表达式数组)
    static func extractCleanRules(from rule: String) -> (mainRule: String, cleanRules: [(pattern: String, replacement: String)]) {
        let parts = rule.components(separatedBy: "##")

        guard parts.count >= 2 else {
            return (rule, [])
        }

        let mainRule = parts[0]
        var cleanRules: [(String, String)] = []

        // 处理净化规则（##pattern##replacement##pattern##replacement...）
        var i = 1
        while i < parts.count {
            let pattern = parts[i]

            // 如果有replacement
            let replacement: String
            if i + 1 < parts.count {
                replacement = parts[i + 1]
                i += 2
            } else {
                // 没有replacement，默认为空字符串
                replacement = ""
                i += 1
            }

            cleanRules.append((pattern, replacement))
        }

        return (mainRule, cleanRules)
    }

    /// 应用净化规则
    /// - Parameters:
    ///   - content: 要净化的内容
    ///   - cleanRules: 净化规则数组
    /// - Returns: 净化后的内容
    static func clean(content: String, with cleanRules: [(pattern: String, replacement: String)]) -> String {
        var result = content

        for (pattern, replacement) in cleanRules {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                continue
            }

            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }

        return result
    }
}

/// 正则OnlyOne处理器（只获取第一个匹配）
class RegexOnlyOneParser {
    /// 检测是否是OnlyOne规则（以##开头，以###结尾）
    static func isOnlyOneRule(_ rule: String) -> Bool {
        return rule.hasPrefix("##") && rule.hasSuffix("###")
    }

    /// 解析OnlyOne规则
    /// - Parameters:
    ///   - rule: 规则字符串（如 `##正则表达式##替换内容###`）
    ///   - content: 要解析的内容
    /// - Returns: 第一个匹配结果
    static func parse(rule: String, content: String) throws -> String? {
        // 移除开头的 ## 和结尾的 ###
        var cleanRule = rule
        if cleanRule.hasPrefix("##") {
            cleanRule = String(cleanRule.dropFirst(2))
        }
        if cleanRule.hasSuffix("###") {
            cleanRule = String(cleanRule.dropLast(3))
        }

        // 分割pattern和replacement
        let parts = cleanRule.components(separatedBy: "##")
        guard parts.count >= 1 else {
            return nil
        }

        let pattern = parts[0]
        let replacement = parts.count > 1 ? parts[1] : "$0"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw RegexError.invalidPattern(pattern)
        }

        let nsContent = content as NSString
        guard let match = regex.firstMatch(in: content, range: NSRange(location: 0, length: nsContent.length)) else {
            return nil
        }

        // 如果有replacement，进行替换
        if replacement != "$0" {
            let matchedString = nsContent.substring(with: match.range)
            let result = regex.stringByReplacingMatches(
                in: matchedString,
                range: NSRange(location: 0, length: matchedString.utf16.count),
                withTemplate: replacement
            )
            return result
        }

        // 否则返回整个匹配
        return nsContent.substring(with: match.range)
    }
}

/// 正则错误类型
enum RegexError: Error, LocalizedError {
    case invalidPattern(String)
    case noMatch

    var errorDescription: String? {
        switch self {
        case .invalidPattern(let pattern):
            return "无效的正则表达式: \(pattern)"
        case .noMatch:
            return "没有匹配结果"
        }
    }
}
