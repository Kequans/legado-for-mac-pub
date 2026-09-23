import Foundation
import CoreFoundation

/// Android AnalyzeUrl 的可移植请求子集；所有请求最终经 NetworkManager 发出。
struct SourceRequest {
    let request: URLRequest
    let encoding: String.Encoding?
    let retries: Int

    static func parse(_ raw: String, baseURL: String, headers: [String: String] = [:],
                      keyword: String? = nil, page: Int = 1, jsLib: String? = nil) throws -> SourceRequest {
        var address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.hasPrefix("@js:") || address.hasPrefix("<js>") {
            address = try JavaScriptEngine.shared.parseJSRule(address, html: "", baseUrl: baseURL, jsLib: jsLib)
        }
        var options: [String: Any] = [:]
        // Only accept a suffix that actually decodes as an options object.
        for index in address.indices where address[index] == "," {
            let suffix = String(address[address.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.hasPrefix("{"), let data = suffix.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                options = object
                address = String(address[..<index])
                break
            }
        }
        if (options["webView"] as? Bool) == true || (options["webView"] as? String)?.lowercased() == "true" ||
            options["webJs"] != nil || options["serverID"] != nil {
            throw SourceRequestError.unsupported("WebView/webJs/serverID")
        }
        let charset = options["charset"] as? String
        let encoding = try charset.map { try textEncoding($0) }
        let bodyEncoding = encoding ?? .utf8
        func expand(_ text: String) throws -> String {
            let escapedKey = try keyword.map { try percentEncode($0, encoding: bodyEncoding) } ?? ""
            let substituted = text.replacingOccurrences(of: "{{key}}", with: escapedKey)
                .replacingOccurrences(of: "{key}", with: escapedKey)
                .replacingOccurrences(of: "{{page}}", with: String(page))
                .replacingOccurrences(of: "{page}", with: String(page))
            return try RuleTemplate.expand(substituted) { expression in
                try JavaScriptEngine.shared.evaluateRule(expression,
                    variables: ["key": keyword ?? "", "page": page, "baseUrl": baseURL], jsLib: jsLib)
            }
        }
        address = try expand(address)
        if let script = options["js"] as? String {
            address = try JavaScriptEngine.shared.evaluateRule(script,
                variables: ["result": address, "baseUrl": baseURL], jsLib: jsLib)
        }
        guard !address.isEmpty, let base = URL(string: baseURL),
              let url = URL(string: address, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        let method = (options["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST"].contains(method) else { throw SourceRequestError.unsupported("method=\(method)") }
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        for key in ["header", "headers"] {
            var extra = options[key] as? [String: Any]
            if let string = options[key] as? String, let data = string.data(using: .utf8) {
                extra = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            for (name, value) in extra ?? [:] { request.setValue(String(describing: value), forHTTPHeaderField: name) }
        }
        if method == "POST" {
            if let body = options["body"] as? String {
                guard let data = try expand(body).data(using: bodyEncoding) else { throw NetworkError.decodingError }
                request.httpBody = data
            } else if let body = options["body"], JSONSerialization.isValidJSONObject(body) {
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        let retry = (options["retry"] as? Int) ?? Int(options["retry"] as? String ?? "") ?? 0
        return SourceRequest(request: request, encoding: encoding, retries: min(max(retry, 0), 5))
    }

    static func textEncoding(_ name: String) throws -> String.Encoding {
        let value = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard value != kCFStringEncodingInvalidId else { throw SourceRequestError.unsupported("charset=\(name)") }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
    }

    private static func percentEncode(_ value: String, encoding: String.Encoding) throws -> String {
        guard let bytes = value.data(using: encoding) else { throw NetworkError.decodingError }
        return bytes.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,126].contains(byte) {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }
}

enum SourceRequestError: Error, LocalizedError {
    case unsupported(String)
    case pageLimit(Int)
    var errorDescription: String? {
        switch self {
        case .unsupported(let feature): return "当前 macOS 解析器不支持书源能力：\(feature)"
        case .pageLimit(let limit): return "分页超过 \(limit) 页，已停止；请检查书源分页规则"
        }
    }
}
