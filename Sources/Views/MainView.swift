import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var showSettings = false
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        NavigationSplitView {
            // 侧边栏
            VStack(spacing: 0) {
                List(selection: $selectedTab) {
                    Label("书架", systemImage: "books.vertical")
                        .tag(0)
                    Label("书源", systemImage: "square.grid.2x2")
                        .tag(1)
                    Label("发现", systemImage: "sparkles")
                        .tag(2)
                    Label("订阅", systemImage: "newspaper")
                        .tag(3)
                    Label("关于", systemImage: "info.circle")
                        .tag(4)
                }
                .listStyle(.sidebar)
                
                Divider()
                
                // 设置按钮
                Button(action: { showSettings = true }) {
                    HStack {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                        Text("设置")
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .navigationTitle("Legado")
        } detail: {
            detailView
                .id(selectedTab)
                .transition(reduceMotion ? .identity : .opacity)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.18),
                    value: selectedTab
                )
        }
        .sheet(isPresented: $appState.showImportBookSource) {
            ImportBookSourceView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: appState.selectedBook) { newBook in
            if let book = newBook, appState.isReading {
                openWindow(id: "reader", value: book)
                // 打开窗口后清空状态，避免重复打开
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appState.selectedBook = nil
                    appState.isReading = false
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case 0:
            BookshelfView()
        case 1:
            BookSourceView()
        case 2:
            DiscoverView()
        case 3:
            RSSView()
        case 4:
            AboutView()
        default:
            BookshelfView()
        }
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
