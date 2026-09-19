import SwiftUI
import AppKit

@main
struct LegadoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    // 读取配置以获取阅读器窗口默认大小
    private let readerConfig = ReaderConfig.load()
    
    init() {
        // 初始化数据库
        DatabaseManager.shared.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 1000, idealWidth: 1400, maxWidth: .infinity, minHeight: 700, idealHeight: 900, maxHeight: .infinity)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("书籍") {
                Button("导入书源") {
                    appState.showImportBookSource = true
                }
                .keyboardShortcut("i", modifiers: [.command])
                
                Button("刷新书架") {
                    Task {
                        await appState.refreshBookshelf()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            
            CommandMenu("设置") {
                Menu("预加载章节数") {
                    ForEach([1, 3, 5, 10, 20], id: \.self) { count in
                        Button("\(count) 章") {
                            var config = MainAppConfig.load()
                            config.preloadChapterCount = count
                            config.save()
                        }
                    }
                }
                
                Button("清理过期缓存") {
                    Task {
                        do {
                            try ChapterContentDAO().cleanExpiredCache()
                            print("✅ 缓存清理完成")
                        } catch {
                            print("❌ 缓存清理失败: \(error)")
                        }
                    }
                }
            }
        }
        
        // 阅读器独立窗口 - 使用配置文件中保存的尺寸
        WindowGroup(id: "reader", for: Book.self) { $book in
            if let book = book {
                ReaderView(book: book)
            } else {
                Text("正在加载...")
            }
        }
        .defaultSize(width: readerConfig.pageWidth, height: readerConfig.pageHeight + 228)
        
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

// macOS 应用程序代理
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用激活策略为常规应用（显示在Dock和菜单栏）
        NSApplication.shared.setActivationPolicy(.regular)
        // 激活应用并将其置于最前
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// 应用程序状态管理
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var showImportBookSource = false
    @Published var selectedBook: Book?
    @Published var isReading = false
    
    private init() {}
    
    func refreshBookshelf() async {
        NotificationCenter.default.post(name: .bookshelfUpdated, object: nil)
    }
}
