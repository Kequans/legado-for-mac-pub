import Foundation
import CFNetwork

/// 网络请求管理器
class NetworkManager: NSObject {
    static let shared = NetworkManager()
    
    private var session: URLSession!
    private var cookieStorage = [String: [HTTPCookie]]()
    
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
    
    // GET 请求
    func get(url: String, headers: [String: String]? = nil) async throws -> String {
        guard let requestUrl = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = ReadConfig.shared.requestTimeout
        
        // 添加基础headers（模拟真实移动端）
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        
        // 添加请求头
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // 添加User-Agent（如果没有设置）
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(ReadConfig.shared.userAgent, forHTTPHeaderField: "User-Agent")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        // 保存Cookie
        var headerFields: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headerFields[String(describing: key)] = String(describing: value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: requestUrl)
        if !cookies.isEmpty {
            saveCookies(cookies, for: url)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // 尝试检测编码
        if let encoding = detectEncoding(from: data, response: httpResponse) {
            return String(data: data, encoding: encoding) ?? ""
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    // POST 请求
    func post(url: String, body: Data?, headers: [String: String]? = nil) async throws -> String {
        guard let requestUrl = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = ReadConfig.shared.requestTimeout
        
        // 添加请求头
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // 添加默认请求头
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(ReadConfig.shared.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        // 保存Cookie
        var headerFields: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headerFields[String(describing: key)] = String(describing: value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: requestUrl)
        if !cookies.isEmpty {
            saveCookies(cookies, for: url)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        if let encoding = detectEncoding(from: data, response: httpResponse) {
            return String(data: data, encoding: encoding) ?? ""
        }
        
        return String(data: data, encoding: .utf8) ?? ""
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
    
    // 保存Cookie
    private func saveCookies(_ cookies: [HTTPCookie], for url: String) {
        cookieStorage[url] = cookies
    }
    
    // 获取Cookie
    func getCookies(for url: String) -> [HTTPCookie]? {
        return cookieStorage[url]
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
