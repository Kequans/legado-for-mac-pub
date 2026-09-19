import Foundation

/// 阅读配置管理
class ReadConfig {
    static let shared = ReadConfig()
    
    private let defaults = UserDefaults.standard
    
    // 字体设置
    var fontSize: Double {
        get { defaults.double(forKey: "fontSize") == 0 ? 18 : defaults.double(forKey: "fontSize") }
        set { defaults.set(newValue, forKey: "fontSize") }
    }
    
    var lineSpacing: Double {
        get { defaults.double(forKey: "lineSpacing") == 0 ? 8 : defaults.double(forKey: "lineSpacing") }
        set { defaults.set(newValue, forKey: "lineSpacing") }
    }
    
    // 颜色设置
    var backgroundColor: String {
        get { defaults.string(forKey: "backgroundColor") ?? "#FFFFFF" }
        set { defaults.set(newValue, forKey: "backgroundColor") }
    }
    
    var textColor: String {
        get { defaults.string(forKey: "textColor") ?? "#000000" }
        set { defaults.set(newValue, forKey: "textColor") }
    }
    
    // 翻页设置
    var enablePageAnimation: Bool {
        get { defaults.bool(forKey: "enablePageAnimation") }
        set { defaults.set(newValue, forKey: "enablePageAnimation") }
    }
    
    // 网络设置
    var userAgent: String {
        get { 
            defaults.string(forKey: "userAgent") ?? 
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        }
        set { defaults.set(newValue, forKey: "userAgent") }
    }
    
    var requestTimeout: Double {
        get { 
            let timeout = defaults.double(forKey: "requestTimeout")
            return timeout == 0 ? 30 : timeout
        }
        set { defaults.set(newValue, forKey: "requestTimeout") }
    }
    
    private init() {}
}

/// 应用配置
class AppConfig {
    static let shared = AppConfig()
    
    private let defaults = UserDefaults.standard
    
    // 启动设置
    var openLastBook: Bool {
        get { defaults.bool(forKey: "openLastBook") }
        set { defaults.set(newValue, forKey: "openLastBook") }
    }
    
    // 更新设置
    var autoCheckUpdate: Bool {
        get { defaults.bool(forKey: "autoCheckUpdate") }
        set { defaults.set(newValue, forKey: "autoCheckUpdate") }
    }
    
    // 代理设置
    var enableProxy: Bool {
        get { defaults.bool(forKey: "enableProxy") }
        set { defaults.set(newValue, forKey: "enableProxy") }
    }
    
    var proxyHost: String {
        get { defaults.string(forKey: "proxyHost") ?? "" }
        set { defaults.set(newValue, forKey: "proxyHost") }
    }
    
    var proxyPort: Int {
        get { defaults.integer(forKey: "proxyPort") }
        set { defaults.set(newValue, forKey: "proxyPort") }
    }
    
    private init() {}
}
