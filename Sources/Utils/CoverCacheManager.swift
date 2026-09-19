import Foundation
import SwiftUI
import CryptoKit

/// 封面缓存管理器
class CoverCacheManager {
    static let shared = CoverCacheManager()
    
    private let cacheDirectory: URL
    private let fileManager = Foundation.FileManager()
    
    // 内存缓存
    private var memoryCache: [String: NSImage] = [:]
    private let maxMemoryCacheSize = 50 // 最多缓存50张图片在内存中
    
    private init() {
        // 获取应用支持目录
        let appSupport = fileManager.urls(for: Foundation.FileManager.SearchPathDirectory.applicationSupportDirectory, in: Foundation.FileManager.SearchPathDomainMask.userDomainMask).first!
        let legadoDir = appSupport.appendingPathComponent("Legado", isDirectory: true)
        cacheDirectory = legadoDir.appendingPathComponent("covers", isDirectory: true)
        
        // 创建缓存目录
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        print("📁 [CoverCache] 缓存目录: \(cacheDirectory.path)")
    }
    
    /// 获取封面图片（先从缓存，缓存不存在则下载）
    /// - Parameters:
    ///   - coverUrl: 封面URL
    ///   - bookUrl: 书籍URL（用作缓存键）
    /// - Returns: 本地缓存路径
    func getCoverImage(coverUrl: String, bookUrl: String) async throws -> String {
        // 生成缓存文件名（使用bookUrl的hash）
        let cacheFileName = bookUrl.toMD5() + ".jpg"
        let cacheFilePath = cacheDirectory.appendingPathComponent(cacheFileName)
        
        // 检查本地缓存
        if fileManager.fileExists(atPath: cacheFilePath.path) {
            print("✅ [CoverCache] 使用本地缓存: \(cacheFileName)")
            return cacheFilePath.path
        }
        
        // 下载封面
        print("⬇️ [CoverCache] 下载封面: \(coverUrl)")
        guard let url = URL(string: coverUrl) else {
            throw CoverCacheError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // 保存到本地
        try data.write(to: cacheFilePath)
        print("💾 [CoverCache] 保存封面: \(cacheFileName)")
        
        return cacheFilePath.path
    }
    
    /// 从内存缓存获取图片
    func getMemoryCachedImage(for path: String) -> NSImage? {
        return memoryCache[path]
    }
    
    /// 缓存图片到内存
    func cacheImageToMemory(image: NSImage, for path: String) {
        // 如果超过最大缓存数，清除最老的
        if memoryCache.count >= maxMemoryCacheSize {
            let keyToRemove = memoryCache.keys.first!
            memoryCache.removeValue(forKey: keyToRemove)
        }
        memoryCache[path] = image
    }
    
    /// 清除过期缓存（超过30天）
    func cleanExpiredCache() {
        let calendar = Calendar.current
        let now = Date()
        
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [Foundation.URLResourceKey.creationDateKey]) else {
            return
        }
        
        var cleanedCount = 0
        for fileURL in contents {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[Foundation.FileAttributeKey.creationDate] as? Date,
               let daysDiff = calendar.dateComponents([.day], from: creationDate, to: now).day,
               daysDiff > 30 {
                try? fileManager.removeItem(at: fileURL)
                cleanedCount += 1
            }
        }
        
        if cleanedCount > 0 {
            print("🗑️ [CoverCache] 清理了 \(cleanedCount) 个过期封面缓存")
        }
    }
    
    /// 获取缓存大小
    func getCacheSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [Foundation.URLResourceKey.fileSizeKey]) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for fileURL in contents {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[Foundation.FileAttributeKey.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        return totalSize
    }
    
    /// 清空所有缓存
    func clearAllCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.removeAll()
        print("🗑️ [CoverCache] 已清空所有封面缓存")
    }
}

enum CoverCacheError: Error {
    case invalidURL
    case downloadFailed
}

// String MD5 扩展
extension String {
    func toMD5() -> String {
        let digest = Insecure.MD5.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
