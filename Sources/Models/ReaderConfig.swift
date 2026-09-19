import Foundation
import SwiftUI

/// 快捷键配置
struct KeyboardShortcut: Codable, Equatable {
    var key: String
    var modifiers: [String]

    static let leftArrow = KeyboardShortcut(key: "leftArrow", modifiers: [])
    static let rightArrow = KeyboardShortcut(key: "rightArrow", modifiers: [])
    static let pageUp = KeyboardShortcut(key: "pageUp", modifiers: [])
    static let pageDown = KeyboardShortcut(key: "pageDown", modifiers: [])
}

/// 阅读器配置管理类
class ReaderConfig: Codable {
    var pageWidth: CGFloat
    var pageHeight: CGFloat
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var backgroundColor: String  // 颜色的十六进制表示
    var textColor: String
    var showToolbar: Bool
    var previousChapterShortcut: KeyboardShortcut
    var nextChapterShortcut: KeyboardShortcut
    
    init(
        pageWidth: CGFloat = 900,
        pageHeight: CGFloat = 800,
        fontSize: CGFloat = 18,
        lineSpacing: CGFloat = 8,
        backgroundColor: String = "#FFFFFF",
        textColor: String = "#000000",
        showToolbar: Bool = true,
        previousChapterShortcut: KeyboardShortcut = .leftArrow,
        nextChapterShortcut: KeyboardShortcut = .rightArrow
    ) {
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.showToolbar = showToolbar
        self.previousChapterShortcut = previousChapterShortcut
        self.nextChapterShortcut = nextChapterShortcut
    }
    
    // MARK: - 文件路径
    private static var configFileURL: URL {
        let fileManager = Foundation.FileManager()
        let appSupport = try! fileManager.url(
            for: Foundation.FileManager.SearchPathDirectory.applicationSupportDirectory,
            in: Foundation.FileManager.SearchPathDomainMask.userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let legadoDir = appSupport.appendingPathComponent("Legado")
        
        // 确保目录存在
        try? fileManager.createDirectory(at: legadoDir, withIntermediateDirectories: true)
        
        return legadoDir.appendingPathComponent("reader_config.json")
    }
    
    // MARK: - 加载配置
    static func load() -> ReaderConfig {
        let fileManager = Foundation.FileManager()
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            print("配置文件不存在，使用默认配置")
            return ReaderConfig()
        }
        
        do {
            let data = try Data(contentsOf: configFileURL)
            let config = try JSONDecoder().decode(ReaderConfig.self, from: data)
            print("加载配置成功: \(configFileURL.path)")
            return config
        } catch {
            print("加载配置失败: \(error)，使用默认配置")
            return ReaderConfig()
        }
    }
    
    // MARK: - 保存配置
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Self.configFileURL)
            print("配置已保存: \(Self.configFileURL.path)")
        } catch {
            print("保存配置失败: \(error)")
        }
    }
    
    // MARK: - 颜色转换工具
    func getBackgroundColor() -> Color {
        return Color(hex: backgroundColor)
    }
    
    func getTextColor() -> Color {
        return Color(hex: textColor)
    }
    
    static func colorToHex(_ color: Color) -> String {
        #if os(macOS)
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            return "#FFFFFF"
        }
        let red = Int(nsColor.redComponent * 255)
        let green = Int(nsColor.greenComponent * 255)
        let blue = Int(nsColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
        #else
        return "#FFFFFF"
        #endif
    }
}

// MARK: - Color 扩展：支持十六进制颜色
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
