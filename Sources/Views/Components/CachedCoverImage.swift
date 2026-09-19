import SwiftUI
import AppKit

/// 支持缓存的封面图片视图
struct CachedCoverImage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Binding<Book>
    let width: CGFloat
    let height: CGFloat
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.5)
                            } else {
                                Image(systemName: "book")
                                    .font(width > 80 ? .title : .body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
            }
        }
        .frame(width: width, height: height)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: image != nil
        )
        .task(id: book.wrappedValue.displayCover) {
            await loadCover()
        }
    }
    
    private func loadCover() async {
        let currentBook = book.wrappedValue
        let coverPath = currentBook.displayCover
        
        guard !coverPath.isEmpty else {
            image = nil
            return
        }
        
        // 如果已经是本地路径，直接加载
        if coverPath.hasPrefix("/") {
            if let loadedImage = NSImage(contentsOfFile: coverPath) {
                image = loadedImage
                CoverCacheManager.shared.cacheImageToMemory(image: loadedImage, for: coverPath)
            }
            return
        }
        
        // 检查内存缓存
        if let cachedImage = CoverCacheManager.shared.getMemoryCachedImage(for: coverPath) {
            image = cachedImage
            return
        }
        
        // 异步加载封面
        guard let coverUrl = currentBook.coverUrl, !coverUrl.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        do {
            let localPath = try await CoverCacheManager.shared.getCoverImage(
                coverUrl: coverUrl,
                bookUrl: currentBook.bookUrl
            )
            guard !Task.isCancelled else { return }

            if let loadedImage = NSImage(contentsOfFile: localPath) {
                image = loadedImage
                CoverCacheManager.shared.cacheImageToMemory(image: loadedImage, for: localPath)
            }

            // 封面下载完成后再异步落库，避免阻塞封面网格的主线程。
            if currentBook.localCoverPath != localPath {
                var updatedBook = currentBook
                updatedBook.localCoverPath = localPath
                book.wrappedValue = updatedBook
                Task.detached(priority: .utility) {
                    try? BookDAO().save(updatedBook)
                }
            }
        } catch {
            if !Task.isCancelled {
                print("❌ [CachedCoverImage] 加载封面失败: \(error)")
            }
        }
    }
}
