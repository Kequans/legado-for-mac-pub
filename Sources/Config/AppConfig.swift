import Foundation

/// 主应用配置（预加载等）
struct MainAppConfig: Codable {
    /// 预加载章节数量
    var preloadChapterCount: Int
    
    /// 是否跳过书籍详情页（直接进入阅读）
    var skipBookDetail: Bool
    
    /// 默认配置
    static let `default` = MainAppConfig(
        preloadChapterCount: 10,
        skipBookDetail: false
    )
    
    /// 配置文件路径
    static var configURL: URL {
        let fileManager = Foundation.FileManager()
        let appSupport = try! fileManager.url(
            for: Foundation.FileManager.SearchPathDirectory.applicationSupportDirectory,
            in: Foundation.FileManager.SearchPathDomainMask.userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let legadoDir = appSupport.appendingPathComponent("Legado")
        try? fileManager.createDirectory(at: legadoDir, withIntermediateDirectories: true)
        return legadoDir.appendingPathComponent("main_app_config.json")
    }
    
    /// 加载配置
    static func load() -> MainAppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(MainAppConfig.self, from: data) else {
            return .default
        }
        return config
    }
    
    /// 保存配置
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: MainAppConfig.configURL)
        print("主应用配置已保存: \(MainAppConfig.configURL.path)")
    }
}
