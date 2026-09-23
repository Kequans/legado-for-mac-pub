import Foundation
import CFNetwork

/// 网络请求管理器
class NetworkManager: NSObject {
    static let shared = NetworkManager()
    
    private var session: URLSession!
    
    private override init() {
        super.init()
        session = makeSession()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = ReadConfig.shared.requestTimeout
        config.timeoutIntervalForResource = 120  // 资源超时120秒
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // 禁用缓存
        config.waitsForConnectivity = true  // 等待连接可用
        
        // 允许蜂窝网络连接
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        // HTTP配置
        config.httpMaximumConnectionsPerHost = 6
        config.httpShouldUsePipelining = false  // 禁用HTTP管道
        
        // TLS配置（允许更宽松的证书验证）
        config.tlsMinimumSupportedProtocolVersion = .TLSv12

        if AppConfig.shared.enableProxy,
           !AppConfig.shared.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           AppConfig.shared.proxyPort > 0 {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: AppConfig.shared.proxyHost,
                kCFNetworkProxiesHTTPPort as String: AppConfig.shared.proxyPort,
                kCFNetworkProxiesHTTPSProxy as String: AppConfig.shared.proxyHost,
                kCFNetworkProxiesHTTPSPort as String: AppConfig.shared.proxyPort
            ]
        }

        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func reloadConfiguration() {
        session.invalidateAndCancel()
        session = makeSession()
    }
    
    struct Response {
        let text: String
        let url: URL
        let statusCode: Int
    }

    /// 可注入 URLSession，供离线请求回归使用。
    init(session: URLSession) {
        super.init()
        self.session = session
    }

    func fetch(_ source: SourceRequest) async throws -> Response {
        for attempt in 0...source.retries {
            try Task.checkCancellation()
            do {
                return try await response(for: source.request, encoding: source.encoding)
            } catch {
                try Task.checkCancellation()
                let transient: Bool
                if case NetworkError.httpError(let status) = error {
                    transient = status == 429 || status >= 500
                } else {
                    transient = (error as? URLError).map { [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains($0.code) } ?? false
                }
                guard transient, attempt < source.retries else { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 200_000_000)
            }
        }
        throw NetworkError.invalidResponse
    }

    func response(for original: URLRequest, encoding: String.Encoding? = nil) async throws -> Response {
        try Task.checkCancellation()
        var request = original
        request.timeoutInterval = ReadConfig.shared.requestTimeout
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(ReadConfig.shared.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil { request.setValue("*/*", forHTTPHeaderField: "Accept") }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, let finalURL = http.url else { throw NetworkError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw NetworkError.httpError(statusCode: http.statusCode) }
        let selected = encoding ?? detectEncoding(from: data, response: http) ?? .utf8
        guard let text = String(data: data, encoding: selected) else { throw NetworkError.decodingError }
        return Response(text: text, url: finalURL, statusCode: http.statusCode)
    }

    func get(url: String, headers: [String: String]? = nil) async throws -> String {
        guard let url = URL(string: url) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers
        return try await response(for: request).text
    }

    func post(url: String, body: Data?, headers: [String: String]? = nil) async throws -> String {
        guard let url = URL(string: url) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.allHTTPHeaderFields = headers
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return try await response(for: request).text
    }

    // 下载图片
    func downloadImage(url: String) async throws -> Data {
        guard let requestUrl = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: requestUrl)
        request.setValue(ReadConfig.shared.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = ReadConfig.shared.requestTimeout
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse
        }
        
        return data
    }
    
    // 检测编码
    private func detectEncoding(from data: Data, response: HTTPURLResponse) -> String.Encoding? {
        if let charset = response.textEncodingName,
           let encoding = try? SourceRequest.textEncoding(charset) { return encoding }
        // 1. 从Content-Type获取
        if let contentType = response.allHeaderFields["Content-Type"] as? String {
            if contentType.contains("charset=gbk") || contentType.contains("charset=GBK") {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            } else if contentType.contains("charset=utf-8") || contentType.contains("charset=UTF-8") {
                return .utf8
            }
        }
        
        // 2. 从HTML meta标签检测
        if let htmlString = String(data: data, encoding: .utf8) {
            if htmlString.contains("charset=gbk") || htmlString.contains("charset=GBK") {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            }
        }
        
        // 3. 默认UTF-8
        return .utf8
    }
    
    func getCookies(for url: String) -> [HTTPCookie]? {
        guard let url = URL(string: url) else { return nil }
        return HTTPCookieStorage.shared.cookies(for: url)
    }

}

// MARK: - URLSessionDelegate
extension NetworkManager: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // 交给系统验证证书，避免书源网络请求绕过 TLS 校验。
        completionHandler(.performDefaultHandling, nil)
    }
}

// 网络错误
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let statusCode):
            return "HTTP错误: \(statusCode)"
        case .decodingError:
            return "解码失败"
        }
    }
}
