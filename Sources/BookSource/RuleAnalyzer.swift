import Foundation
import JavaScriptCore

/// 规则解析器 - 支持CSS、XPath、JSON、JS混合规则
class RuleAnalyzer {
    enum RuleMode {
        case `default`  // CSS选择器
        case xpath      // XPath
        case json       // JSONPath
        case js         // JavaScript
        case regex      // 正则表达式
    }
    
    struct RuleSegment {
        let content: String
        let mode: RuleMode
    }
    
    /// 将规则字符串拆分为多个片段
    /// - Parameter ruleStr: 规则字符串
    /// - Returns: 规则片段数组
    static func splitRule(_ ruleStr: String) -> [RuleSegment] {
        var segments: [RuleSegment] = []
        // 正则匹配 <js>...</js> 或 @js:...
        let jsPattern = #"<js>([\s\S]*?)<\/js>|@js:([\s\S]*?)(?=<js>|@js:|$)"#
        guard let regex = try? NSRegularExpression(pattern: jsPattern, options: [.caseInsensitive]) else {
            // 如果正则创建失败，返回整个规则作为默认模式
            return [RuleSegment(content: ruleStr, mode: inferMode(ruleStr))]
        }
        
        let nsString = ruleStr as NSString
        let matches = regex.matches(in: ruleStr, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var lastEnd = 0
        
        for match in matches {
            // 添加JS之前的部分（如果有）
            if match.range.location > lastEnd {
                let range = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let beforeJS = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !beforeJS.isEmpty {
                    segments.append(RuleSegment(content: beforeJS, mode: inferMode(beforeJS)))
                }
            }
            
            // 添加JS部分
            // group(1) = <js>内容</js>中的内容
            // group(2) = @js:后的内容
            var jsContent = ""
            if match.range(at: 1).location != NSNotFound {
                jsContent = nsString.substring(with: match.range(at: 1))
            } else if match.range(at: 2).location != NSNotFound {
                jsContent = nsString.substring(with: match.range(at: 2))
            }
            
            if !jsContent.isEmpty {
                segments.append(RuleSegment(content: jsContent.trimmingCharacters(in: .whitespacesAndNewlines), mode: .js))
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        // 添加最后剩余的部分
        if lastEnd < nsString.length {
            let remaining = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                segments.append(RuleSegment(content: remaining, mode: inferMode(remaining)))
            }
        }
        
        // 如果没有匹配到任何JS，返回整个规则
        if segments.isEmpty {
            segments.append(RuleSegment(content: ruleStr, mode: inferMode(ruleStr)))
        }
        
        return segments
    }
    
    /// 推断规则模式
    private static func inferMode(_ rule: String) -> RuleMode {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // XPath: 以 / 开头或者有 @XPath: 前缀
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("@XPath:") {
            return .xpath
        }
        
        // JSON: 以 $. 或 $[ 开头或者有 @Json: 前缀
        if trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") || trimmed.hasPrefix("@Json:") {
            return .json
        }
        
        // Regex: 以 : 开头（AllInOne模式）
        if trimmed.hasPrefix(":") {
            return .regex
        }
        
        // 默认为CSS选择器
        return .default
    }
    
    /// 清理规则前缀
    static func cleanRulePrefix(_ rule: String, mode: RuleMode) -> String {
        var cleaned = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch mode {
        case .xpath:
            if cleaned.hasPrefix("@XPath:") {
                cleaned = String(cleaned.dropFirst(7))
            }
        case .json:
            if cleaned.hasPrefix("@Json:") {
                cleaned = String(cleaned.dropFirst(6))
            }
        case .regex:
            if cleaned.hasPrefix(":") {
                cleaned = String(cleaned.dropFirst(1))
            }
        case .default:
            if cleaned.hasPrefix("@CSS:") {
                cleaned = String(cleaned.dropFirst(5))
            } else if cleaned.hasPrefix("@@") {
                cleaned = String(cleaned.dropFirst(2))
            }
        case .js:
            // JS规则在splitRule时已经清理
            break
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
