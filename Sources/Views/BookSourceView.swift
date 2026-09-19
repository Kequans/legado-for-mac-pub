import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BookSourceView: View {
    @StateObject private var viewModel = BookSourceViewModel()
    @State private var showImport = false
    @State private var showAddNew = false
    @State private var selectedSource: BookSource?
    @State private var searchText = ""
    @State private var selectedSources: Set<String> = [] // 选中的书源ID集合
    @State private var isSelectionMode = false // 是否处于选择模式

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("书源管理")
                    .font(.title)
                    .bold()

                Spacer()

                if isSelectionMode {
                    // 选择模式下的操作按钮
                    Button(action: {
                        deleteSelectedSources()
                    }) {
                        Label("删除选中", systemImage: "trash")
                    }
                    .disabled(selectedSources.isEmpty)

                    Button(action: {
                        exportSelectedSources()
                    }) {
                        Label("导出选中", systemImage: "square.and.arrow.up")
                    }
                    .disabled(selectedSources.isEmpty)

                    Button("取消") {
                        isSelectionMode = false
                        selectedSources.removeAll()
                    }
                } else {
                    // 正常模式下的按钮
                    Button(action: {
                        isSelectionMode = true
                    }) {
                        Label("选择", systemImage: "checkmark.circle")
                    }

                    Button(action: { showAddNew = true }) {
                        Label("自定义", systemImage: "plus")
                    }

                    Button(action: { showImport = true }) {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            
            // 搜索栏
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索书源", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
            
            Divider()
                .padding(.top)
            
            // 书源列表
            List(filteredSources) { source in
                HStack(spacing: 12) {
                    // 选择模式下显示复选框
                    if isSelectionMode {
                        Button(action: {
                            toggleSelection(source)
                        }) {
                            Image(systemName: selectedSources.contains(source.bookSourceUrl) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedSources.contains(source.bookSourceUrl) ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    BookSourceRow(source: source)
                }
                .onTapGesture {
                    if isSelectionMode {
                        toggleSelection(source)
                    } else {
                        selectedSource = source
                    }
                }
                .contextMenu {
                    if !isSelectionMode {
                        Button(source.enabled ? "禁用" : "启用") {
                            viewModel.toggleEnabled(source)
                        }
                        Button("编辑") {
                            selectedSource = source
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            viewModel.deleteSource(source)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportBookSourceView()
        }
        .onDisappear {
            // 当导入窗口关闭时刷新书源列表
            Task {
                await viewModel.loadSources()
            }
        }
        .sheet(isPresented: $showAddNew) {
            BookSourceEditView(bookSource: nil)
        }
        .sheet(item: $selectedSource) { source in
            BookSourceEditView(bookSource: source)
        }
        .task {
            await viewModel.loadSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookSourceImported)) { _ in
            // 收到书源导入通知时刷新
            Task {
                await viewModel.loadSources()
            }
        }
    }
    
    private var filteredSources: [BookSource] {
        if searchText.isEmpty {
            return viewModel.sources
        } else {
            return viewModel.sources.filter {
                $0.bookSourceName.localizedCaseInsensitiveContains(searchText) ||
                $0.bookSourceUrl.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func toggleSelection(_ source: BookSource) {
        if selectedSources.contains(source.bookSourceUrl) {
            selectedSources.remove(source.bookSourceUrl)
        } else {
            selectedSources.insert(source.bookSourceUrl)
        }
    }

    private func deleteSelectedSources() {
        for sourceUrl in selectedSources {
            if let source = viewModel.sources.first(where: { $0.bookSourceUrl == sourceUrl }) {
                viewModel.deleteSource(source)
            }
        }
        selectedSources.removeAll()
        isSelectionMode = false
    }

    private func exportSelectedSources() {
        // 获取选中的书源
        let sourcesToExport = viewModel.sources.filter { selectedSources.contains($0.bookSourceUrl) }

        guard !sourcesToExport.isEmpty else {
            print("❌ 没有选中的书源")
            return
        }

        // 创建保存面板
        let savePanel = NSSavePanel()
        savePanel.title = "导出书源"
        savePanel.message = "选择保存位置"
        savePanel.nameFieldStringValue = "书源导出_\(Date().formatted(date: .numeric, time: .omitted)).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else {
                print("❌ 用户取消导出")
                return
            }

            do {
                // 将书源转换为JSON
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(sourcesToExport)

                // 写入文件
                try jsonData.write(to: url)

                print("✅ 成功导出 \(sourcesToExport.count) 个书源到: \(url.path)")

                // 导出成功后退出选择模式
                selectedSources.removeAll()
                isSelectionMode = false
            } catch {
                print("❌ 导出失败: \(error)")
            }
        }
    }
}

struct BookSourceRow: View {
    let source: BookSource
    
    var body: some View {
        HStack(spacing: 12) {
            // 启用状态指示器
            Circle()
                .fill(source.enabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(source.bookSourceName)
                    .font(.headline)
                
                Text(source.bookSourceUrl)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let group = source.bookSourceGroup, !group.isEmpty {
                    Text(group)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(typeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if source.respondTime < 5000 {
                    Text("快速")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if source.respondTime < 15000 {
                    Text("正常")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else {
                    Text("较慢")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var typeText: String {
        switch source.bookSourceType {
        case 0: return "文本"
        case 1: return "音频"
        case 2: return "图片"
        case 3: return "文件"
        default: return "未知"
        }
    }
}

@MainActor
class BookSourceViewModel: ObservableObject {
    @Published var sources: [BookSource] = []
    private let bookSourceDAO = BookSourceDAO()
    
    func loadSources() async {
        do {
            sources = try bookSourceDAO.getAll()
        } catch {
            print("加载书源失败: \(error)")
        }
    }
    
    func toggleEnabled(_ source: BookSource) {
        do {
            try bookSourceDAO.updateEnabled(bookSourceUrl: source.bookSourceUrl, enabled: !source.enabled)
            if let index = sources.firstIndex(where: { $0.id == source.id }) {
                sources[index].enabled.toggle()
            }
        } catch {
            print("更新书源状态失败: \(error)")
        }
    }
    
    func deleteSource(_ source: BookSource) {
        do {
            try bookSourceDAO.delete(bookSourceUrl: source.bookSourceUrl)
            sources.removeAll { $0.id == source.id }
        } catch {
            print("删除书源失败: \(error)")
        }
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
