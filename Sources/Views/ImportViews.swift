import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImportBookSourceView: View {
    @Environment(\.dismiss) var dismiss
    @State private var sourceText = ""
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var showFilePicker = false
    @State private var showUrlSheet = false
    @State private var urlInput = ""
    @FocusState private var isTextEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("导入书源")
                .font(.title2)
                .bold()
            
            // 导入方式选择
            HStack(spacing: 20) {
                Button(action: { showFilePicker = true }) {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                        Text("从文件导入")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { showUrlSheet = true }) {
                    VStack {
                        Image(systemName: "link")
                            .font(.largeTitle)
                        Text("从URL导入")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            // 文本输入
            VStack(alignment: .leading, spacing: 8) {
                Text("或粘贴书源JSON:")
                    .font(.headline)
                
                ScrollView {
                    TextEditor(text: $sourceText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .focused($isTextEditorFocused)
                }
                .frame(height: 200)
                .border(Color.gray.opacity(0.3))
            }
            .padding(.horizontal)
            
            // 导入结果
            if let result = importResult {
                Text(result)
                    .foregroundColor(result.contains("成功") ? .green : .red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // 按钮组
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("导入") {
                    Task {
                        await importSources()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceText.isEmpty || isImporting)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadFromFile(url)
                }
            case .failure(let error):
                importResult = "文件选择失败: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showUrlSheet) {
            UrlInputSheet(urlInput: $urlInput) { url in
                Task {
                    await importFromUrl(url)
                }
            }
        }
    }
    
    private func loadFromFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                sourceText = text
            }
        } catch {
            importResult = "读取文件失败: \(error.localizedDescription)"
        }
    }
    
    private func importFromUrl(_ url: String) async {
        guard let _ = URL(string: url) else {
            importResult = "无效的URL"
            return
        }
        
        isImporting = true
        importResult = "正在下载..."
        
        do {
            let content = try await NetworkManager.shared.get(url: url)
            sourceText = content
            await importSources()
        } catch {
            importResult = "下载失败: \(error.localizedDescription)"
            isImporting = false
        }
    }
    
    private func importSources() async {
        isImporting = true
        importResult = nil
        
        let decoder = JSONDecoder()
            
            guard let data = sourceText.data(using: .utf8) else {
                importResult = "无法转换文本为数据"
                isImporting = false
                return
            }
            
            // 先尝试解析为数组
            do {
                let sources = try decoder.decode([BookSource].self, from: data)
                let bookSourceDAO = BookSourceDAO()
                try bookSourceDAO.saveAll(sources)
                importResult = "成功导入 \(sources.count) 个书源"
                
                // 发送导入成功通知
                NotificationCenter.default.post(name: .bookSourceImported, object: nil)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
                isImporting = false
                return
            } catch let arrayError {
                print("数组解析失败: \(arrayError)")
                
                // 再尝试解析为单个对象
                do {
                    let source = try decoder.decode(BookSource.self, from: data)
                    let bookSourceDAO = BookSourceDAO()
                    try bookSourceDAO.save(source)
                    importResult = "成功导入 1 个书源"
                    
                    // 发送导入成功通知
                    NotificationCenter.default.post(name: .bookSourceImported, object: nil)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                    isImporting = false
                    return
                } catch let objectError {
                    print("对象解析失败: \(objectError)")
                    
                    // 提供详细的错误信息
                    if let decodingError = objectError as? DecodingError {
                        switch decodingError {
                        case .typeMismatch(let type, let context):
                            importResult = "类型不匹配: \(type), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                        case .valueNotFound(let type, let context):
                            importResult = "缺少必需字段: \(type), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                        case .keyNotFound(let key, let context):
                            importResult = "缺少键: \(key.stringValue), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
                        case .dataCorrupted(let context):
                            importResult = "数据损坏: \(context.debugDescription)"
                        @unknown default:
                            importResult = "未知解码错误: \(objectError.localizedDescription)"
                        }
                    } else {
                        importResult = "JSON格式不正确: \(objectError.localizedDescription)"
                    }
                }
            }
        isImporting = false
    }
}

struct ImportBookView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showSearchView = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("导入书籍")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("取消") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // 导入选项
            VStack(spacing: 16) {
                Button(action: chooseLocalBooks) {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("导入TXT/EPUB文件")
                                .font(.headline)
                            Text("从本地文件系统导入书籍")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: { showSearchView = true }) {
                    HStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("在线搜索导入")
                                .font(.headline)
                            Text("通过书源搜索并导入书籍")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: chooseAndroidBookshelf) {
                    HStack(spacing: 16) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)
                            .frame(width: 50)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("导入 Android 书架")
                                .font(.headline)
                            Text("导入 Legado 导出的书架 JSON")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 600, height: 420)
        .sheet(isPresented: $showSearchView) {
            OnlineSearchView()
        }
    }

    private func chooseLocalBooks() {
        let panel = NSOpenPanel()
        panel.title = "选择 TXT 或 EPUB 文件"
        panel.message = "可以一次选择多个本地书籍"
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "epub")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            importLocalBooks(panel.urls)
        }
    }

    private func chooseAndroidBookshelf() {
        let panel = NSOpenPanel()
        panel.title = "选择 Android 书架 JSON"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importBookshelf(from: url)
        }
    }
    
    private func importLocalBooks(_ urls: [URL]) {
        Task {
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                
                do {
                    let bookUrl = url.path

                    if url.pathExtension.lowercased() == "epub" {
                        let imported = try EPUBImporter.importBook(from: url, bookUrl: bookUrl)
                        var book = Book(bookUrl: bookUrl, name: imported.title, author: imported.author)
                        book.origin = "local"
                        book.type = .file
                        book.totalChapterNum = imported.chapters.count
                        book.latestChapterTitle = imported.chapters.last?.title

                        // 重新导入同一路径时清理旧章节缓存，避免复用旧内容。
                        FileUtils.clearBookCache(bookUrl: bookUrl)
                        _ = FileUtils.cacheLocalBookSource(bookUrl: bookUrl, content: imported.sourceContent)
                        try BookDAO().save(book)
                        try BookChapterDAO().deleteChapters(bookUrl: bookUrl)
                        try BookChapterDAO().saveAll(imported.chapters)
                        print("成功导入 EPUB: \(imported.title), 章节数: \(imported.chapters.count)")
                        continue
                    }

                    // 尝试多种编码读取文本文件
                    let content = try readTextFileWithEncoding(url: url)
                    let bookName = url.deletingPathExtension().lastPathComponent
                    
                    // 创建书籍对象
                    var book = Book(bookUrl: bookUrl, name: bookName, author: "本地文件")
                    book.origin = "local"
                    book.type = .text
                    
                    // 解析章节
                    let chapters = parseChapters(content: content, bookUrl: bookUrl)
                    book.totalChapterNum = chapters.count
                    if let first = chapters.first {
                        book.latestChapterTitle = first.title
                    }
                    
                    // 只保存一个规范化源文件，章节正文在打开时按范围读取。
                    FileUtils.clearBookCache(bookUrl: bookUrl)
                    _ = FileUtils.cacheLocalBookSource(bookUrl: bookUrl, content: content)

                    // 保存到数据库
                    let bookDAO = BookDAO()
                    let chapterDAO = BookChapterDAO()
                    
                    try bookDAO.save(book)
                    try chapterDAO.deleteChapters(bookUrl: bookUrl)
                    try chapterDAO.saveAll(chapters)
                    
                    print("成功导入书籍: \(bookName), 章节数: \(chapters.count)")
                } catch {
                    print("导入失败 \(url.lastPathComponent): \(error)")
                }
            }
            
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func importBookshelf(from url: URL) {
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let books = try BookImportService.decodeBooks(from: data)

                try BookDAO().saveAll(books)
                await MainActor.run { dismiss() }
            } catch {
                print("导入 Android 书架失败: \(error.localizedDescription)")
            }
        }
    }
    
    // 尝试多种编码读取文本文件
    private func readTextFileWithEncoding(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        
        // 尝试的编码列表（按优先级）
        let encodings: [String.Encoding] = [
            .utf8,                                                                     // UTF-8
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(      // GBK/GB18030 (简体中文 Windows)
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(      // GB2312 (简体中文)
                CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
            )),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(      // Big5 (繁体中文)
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )),
            .utf16,                                                                    // UTF-16
            .ascii,                                                                    // ASCII
            .isoLatin1                                                                 // ISO Latin 1
        ]
        
        // 依次尝试各种编码
        for encoding in encodings {
            if let content = String(data: data, encoding: encoding) {
                // 验证内容是否有效（不全是乱码）
                if isValidTextContent(content) {
                    return content
                }
            }
        }
        
        // 如果所有编码都失败，抛出错误
        throw NSError(domain: "TextEncoding", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "无法识别文件编码，请尝试转换为 UTF-8 格式"
        ])
    }
    
    // 验证文本内容是否有效
    private func isValidTextContent(_ text: String) -> Bool {
        // 简单验证：如果文本不为空且包含可打印字符
        guard !text.isEmpty else { return false }
        
        // 检查是否包含合理的中文字符或ASCII字符
        let chineseRange = text.range(of: "[\\u4e00-\\u9fa5]", options: .regularExpression)
        let asciiPrintableRange = text.range(of: "[a-zA-Z0-9]", options: .regularExpression)
        
        return chineseRange != nil || asciiPrintableRange != nil
    }
    
    private func parseChapters(content: String, bookUrl: String) -> [BookChapter] {
        var chapters: [BookChapter] = []
        
        // 简单的正则匹配章节
        // 匹配 "第x章" 或 "第x节" 等
        let pattern = "(?m)^\\s*第[0-9一二三四五六七八九十百千]+[章回节卷集部篇].*$"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let nsString = content as NSString
            let results = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
            
            if results.isEmpty {
                // 如果没有匹配到章节，则作为一整章
                var chapter = BookChapter(url: "\(bookUrl)_0", title: "全文", bookUrl: bookUrl, index: 0)
                chapter.start = 0
                chapter.end = Int64(content.utf8.count)
                chapters.append(chapter)
                print("未识别到章节标题，作为单章处理")
            } else {
                print("识别到 \(results.count) 个章节标题")
                var chapterList: [(index: Int, title: String, start: Int, end: Int)] = []
                
                // 收集所有章节位置
                for (idx, result) in results.enumerated() {
                    let titleRange = result.range
                    let title = nsString.substring(with: titleRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = titleRange.location
                    let end = idx < results.count - 1 ? results[idx + 1].range.location : nsString.length
                    chapterList.append((index: idx, title: title, start: start, end: end))
                }
                
                // 生成章节对象
                for (idx, title, start, end) in chapterList {
                    var chapter = BookChapter(url: "\(bookUrl)_\(idx)", title: title, bookUrl: bookUrl, index: idx)
                    chapter.start = Int64(utf8Offset(forUTF16Offset: start, in: content))
                    chapter.end = Int64(utf8Offset(forUTF16Offset: end, in: content))
                    chapters.append(chapter)
                }
            }
        } catch {
            print("正则解析失败: \(error)")
            // 降级为单章
            var chapter = BookChapter(url: "\(bookUrl)_0", title: "全文", bookUrl: bookUrl, index: 0)
            chapter.start = 0
            chapter.end = Int64(content.utf8.count)
            chapters.append(chapter)
        }
        
        return chapters
    }

    private func utf8Offset(forUTF16Offset offset: Int, in content: String) -> Int {
        guard offset > 0 else { return 0 }
        let stringIndex = String.Index(utf16Offset: offset, in: content)
        return content[..<stringIndex].utf8.count
    }
}

struct BookDetailView: View {
    let book: Book
    var hideActions: Bool = false  // 是否隐藏操作按钮（阅读页调用时使用）
    @Environment(\.dismiss) var dismiss
    @State private var skipDetailNextTime: Bool
    
    init(book: Book, hideActions: Bool = false) {
        self.book = book
        self.hideActions = hideActions
        // 从书籍自身的设置读取
        _skipDetailNextTime = State(initialValue: book.skipDetailPage)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 封面和基本信息
                HStack(alignment: .top, spacing: 16) {
                    AsyncImage(url: URL(string: book.displayCover)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "book")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(width: 150, height: 200)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(book.name)
                            .font(.title)
                            .bold()
                        
                        Text(book.author)
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        if let kind = book.kind {
                            Text(kind)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if book.totalChapterNum > 0 {
                            Text("共 \(book.totalChapterNum) 章")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let latest = book.latestChapterTitle {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最新:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(latest)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding()
                
                Divider()
                
                // 简介
                VStack(alignment: .leading, spacing: 8) {
                    Text("简介")
                        .font(.headline)
                    
                    Text(book.displayIntro)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(hideActions ? nil : 8)
                }
                .padding()
                
                if !hideActions {
                    Spacer()
                }
                
                // 操作按钮
                if !hideActions {
                    // 跳过详情页选项
                    HStack {
                        Toggle("下次直接进入阅读", isOn: $skipDetailNextTime)
                            .font(.caption)
                        Text("勾选后，点击该书籍将不再显示此页面")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    HStack {
                        Button("取消") {
                            dismiss()
                        }
                        
                        Spacer()
                        
                        Button("开始阅读") {
                            // 先保存跳过详情页设置到该书籍
                            if skipDetailNextTime != book.skipDetailPage {
                                var updatedBook = book
                                updatedBook.skipDetailPage = skipDetailNextTime
                                try? BookDAO().save(updatedBook)
                                print("✅ [\(book.name)] 跳过详情页设置已更新: \(skipDetailNextTime)")
                            }
                            
                            // 从数据库重新加载书籍以获取最新的阅读进度和skipDetailPage设置
                            let bookDAO = BookDAO()
                            do {
                                if var freshBook = try bookDAO.get(bookUrl: book.bookUrl) {
                                    // 更新lastCheckTime为当前时间，使其排到书架首位
                                    freshBook.lastCheckTime = Int64(Date().timeIntervalSince1970)
                                    try? bookDAO.save(freshBook)
                                    
                                    print("✅ [BookDetailView] 从数据库加载书籍 - durChapterIndex: \(freshBook.durChapterIndex), skipDetailPage: \(freshBook.skipDetailPage)")
                                    AppState.shared.selectedBook = freshBook
                                    AppState.shared.isReading = true
                                } else {
                                    print("⚠️ [BookDetailView] 数据库中找不到该书籍，使用传入的 book 对象")
                                    AppState.shared.selectedBook = book
                                    AppState.shared.isReading = true
                                }
                            } catch {
                                print("❌ [BookDetailView] 加载书籍失败: \(error)")
                                AppState.shared.selectedBook = book
                                AppState.shared.isReading = true
                            }
                            
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 550, height: hideActions ? 400 : 600)
        .overlay(alignment: .topTrailing) {
            if hideActions {
                Text("按 ESC 退出")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
    }
}

// MARK: - URL 输入 Sheet
struct UrlInputSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var urlInput: String
    let onImport: (String) -> Void
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("输入书源URL")
                .font(.headline)
            
            TextField("https://example.com/source.json", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onAppear {
                    isTextFieldFocused = true
                }
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("导入") {
                    onImport(urlInput)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlInput.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - 在线搜索视图
struct OnlineSearchView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [SearchBook] = []
    @State private var isSearching = false
    @State private var hasResults = false // 新增：标记是否有结果
    @State private var selectedSearchBook: SearchBook?
    @State private var errorMessage: String?
    @State private var showError = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchTask: Task<Void, Never>? // 搜索任务引用
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("搜索书籍")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("取消") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // 搜索栏
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("输入书名或作者", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        startSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button("搜索") {
                    startSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.isEmpty || isSearching)
            }
            .padding()
            
            Divider()

            // 搜索结果
            if !hasResults && isSearching {
                // 初始搜索状态：没有结果且正在搜索
                ProgressView("搜索中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                // 错误提示
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("重新搜索") {
                        errorMessage = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !isSearching {
                // 搜索完成但没有结果
                VStack(spacing: 16) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "输入关键词开始搜索" : "未找到相关书籍")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 显示搜索结果（即使搜索还在进行中）
                VStack(spacing: 0) {
                    List(searchResults.indices, id: \.self) { index in
                        SearchResultRow(searchBook: searchResults[index])
                            .onTapGesture {
                                selectedSearchBook = searchResults[index]
                                // 用户点击书籍，停止搜索
                                searchTask?.cancel()
                                isSearching = false
                            }
                    }

                    // 底部加载指示器（搜索进行中）
                    if isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在搜索更多书源...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
        .sheet(item: Binding(
            get: { selectedSearchBook.map { SearchBookWrapper(searchBook: $0) } },
            set: { selectedSearchBook = $0?.searchBook }
        )) { wrapper in
            SearchBookDetailView(searchBook: wrapper.searchBook)
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }
    
    // 计算匹配度（0-100分）
    private func calculateMatchScore(book: SearchBook, keyword: String) -> Int {
        let lowercaseKeyword = keyword.lowercased()
        let lowercaseName = book.name.lowercased()
        let lowercaseAuthor = book.author.lowercased()

        var score = 0

        // 完全匹配书名：100分
        if lowercaseName == lowercaseKeyword {
            return 100
        }

        // 书名包含关键词：80分
        if lowercaseName.contains(lowercaseKeyword) {
            score += 80
            // 关键词在开头：额外加10分
            if lowercaseName.hasPrefix(lowercaseKeyword) {
                score += 10
            }
        }

        // 作者包含关键词：30分
        if lowercaseAuthor.contains(lowercaseKeyword) {
            score += 30
        }

        // 计算字符相似度（Levenshtein距离）
        let nameSimilarity = calculateSimilarity(lowercaseName, lowercaseKeyword)
        score += Int(nameSimilarity * 20) // 最多20分

        return min(score, 100)
    }

    // 计算字符串相似度（简化版Levenshtein距离）
    private func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        let len1 = s1.count
        let len2 = s2.count

        if len1 == 0 { return len2 == 0 ? 1.0 : 0.0 }
        if len2 == 0 { return 0.0 }

        let maxLen = max(len1, len2)
        var matchCount = 0

        // 简单的字符匹配计数
        for char in s2 {
            if s1.contains(char) {
                matchCount += 1
            }
        }

        return Double(matchCount) / Double(maxLen)
    }

    private func startSearch() {
        searchTask?.cancel()
        searchTask = Task {
            await performSearch()
        }
    }

    private func performSearch() async {
        isSearching = true
        hasResults = false
        searchResults = []
        errorMessage = nil
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !keyword.isEmpty else {
            isSearching = false
            return
        }

        do {
            let bookSourceDAO = BookSourceDAO()
            let sources = try bookSourceDAO.getEnabled()

            guard !sources.isEmpty else {
                errorMessage = "没有启用的书源，请先导入并启用书源"
                isSearching = false
                return
            }

            print("🔍 使用 \(sources.count) 个书源进行搜索")
            var uniqueBooks: [String: SearchBook] = [:]

            let maxConcurrent = min(6, sources.count)
            await withTaskGroup(of: (Int, [SearchBook]).self) { group in
                var nextSourceIndex = 0
                var activeTasks = 0

                while activeTasks < maxConcurrent, nextSourceIndex < sources.count {
                    let source = sources[nextSourceIndex]
                    let sourceIndex = nextSourceIndex
                    nextSourceIndex += 1
                    activeTasks += 1

                    group.addTask {
                        do {
                            let results = try await BookSourceEngine.shared.search(
                                keyword: keyword,
                                bookSource: source
                            )
                            print("✅ 书源【\(source.bookSourceName)】找到 \(results.count) 本书")
                            return (sourceIndex, results)
                        } catch {
                            if !Task.isCancelled {
                                print("❌ 书源【\(source.bookSourceName)】搜索失败: \(error.localizedDescription)")
                            }
                            return (sourceIndex, [])
                        }
                    }
                }

                while activeTasks > 0 {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    guard let (_, results) = await group.next() else { break }
                    activeTasks -= 1

                    var newBooks: [SearchBook] = []
                    for book in results {
                        let key = "\(book.name)_\(book.author)"
                        if uniqueBooks[key] == nil {
                            uniqueBooks[key] = book
                            newBooks.append(book)
                        }
                    }

                    if !newBooks.isEmpty {
                        await MainActor.run {
                            searchResults.append(contentsOf: newBooks)
                            hasResults = true
                            searchResults.sort { book1, book2 in
                                calculateMatchScore(book: book1, keyword: keyword) >
                                calculateMatchScore(book: book2, keyword: keyword)
                            }
                        }
                    }

                    if nextSourceIndex < sources.count && !Task.isCancelled {
                        let source = sources[nextSourceIndex]
                        let sourceIndex = nextSourceIndex
                        nextSourceIndex += 1
                        activeTasks += 1

                        group.addTask {
                            do {
                                let results = try await BookSourceEngine.shared.search(
                                    keyword: keyword,
                                    bookSource: source
                                )
                                print("✅ 书源【\(source.bookSourceName)】找到 \(results.count) 本书")
                                return (sourceIndex, results)
                            } catch {
                                if !Task.isCancelled {
                                    print("❌ 书源【\(source.bookSourceName)】搜索失败: \(error.localizedDescription)")
                                }
                                return (sourceIndex, [])
                            }
                        }
                    }
                }

                group.cancelAll()
            }

            guard !Task.isCancelled else {
                isSearching = false
                return
            }

            print("🎉 搜索完成，共找到 \(searchResults.count) 本不重复的书")

            if searchResults.isEmpty {
                errorMessage = "未找到相关书籍"
            }
        } catch {
            errorMessage = "搜索失败: \(error.localizedDescription)"
            print("搜索失败: \(error)")
        }
        
        isSearching = false
    }
}

// MARK: - SearchBook Wrapper (for Identifiable)
struct SearchBookWrapper: Identifiable {
    let id = UUID()
    let searchBook: SearchBook
}

// MARK: - 搜索书籍详情视图
struct SearchBookDetailView: View {
    let searchBook: SearchBook
    @Environment(\.dismiss) var dismiss
    @State private var isAddingToShelf = false
    @State private var addResult: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息区域
            HStack(alignment: .top, spacing: 16) {
                // 封面
                AsyncImage(url: URL(string: searchBook.coverUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "book")
                                .font(.title)
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 100, height: 140)
                .cornerRadius(6)
                .shadow(radius: 2)

                // 书籍信息
                VStack(alignment: .leading, spacing: 8) {
                    Text(searchBook.name)
                        .font(.title2)
                        .bold()
                        .lineLimit(2)

                    Text(searchBook.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // 书源信息（紧凑显示）
                    HStack(spacing: 6) {
                        Text(searchBook.bookSourceName)
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(searchBook.bookSourceUrl)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(4)

                    // 分类标签
                    if let kind = searchBook.kind {
                        Text(kind)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(3)
                    }

                    // 最新章节
                    if let latest = searchBook.latestChapterTitle {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最新:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(latest)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)

            Divider()

            // 简介区域（限制高度）
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("简介")
                        .font(.headline)

                    Text(searchBook.intro ?? "暂无简介")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)

            // 添加结果提示
            if let result = addResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("成功") ? .green : .red)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
            }

            Divider()

            // 底部操作按钮
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("加入书架") {
                    Task {
                        await addToShelf()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAddingToShelf)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500, height: 450)
    }
    
    private func addToShelf() async {
        isAddingToShelf = true
        addResult = nil
        
        do {
            // 获取书源信息
            let bookSourceDAO = BookSourceDAO()
            guard let bookSource = try bookSourceDAO.get(bookSourceUrl: searchBook.bookSourceUrl) else {
                throw NSError(domain: "BookSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "找不到对应的书源: \(searchBook.bookSourceUrl)"])
            }
            
            // 使用 BookSourceEngine 获取完整的书籍信息
            print("📖 开始获取书籍详情: \(searchBook.bookUrl)")
            let engine = BookSourceEngine.shared
            var book = try await engine.getBookInfo(bookUrl: searchBook.bookUrl, bookSource: bookSource, variable: searchBook.variable)

            // 详情页规则可能因站点改版失效，搜索结果中的基本信息仍然可靠。
            engine.mergeSearchResult(searchBook, into: &book, bookSource: bookSource)
            guard !book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookSourceError.parseError
            }
            
            print("📖 书籍详情获取完成, tocUrl: \(book.tocUrl)")
            
            // 保存到书架
            let bookDAO = BookDAO()
            try bookDAO.save(book)
            
            addResult = "成功加入书架"
            
            // 延迟关闭
            try await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                dismiss()
            }
        } catch {
            addResult = "加入失败: \(error.localizedDescription)"
            print("❌ 加入书架失败: \(error)")
        }
        
        isAddingToShelf = false
    }
}

// MARK: - 搜索结果行
struct SearchResultRow: View {
    let searchBook: SearchBook
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: searchBook.coverUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "book")
                            .foregroundColor(.secondary)
                    )
            }
            .frame(width: 50, height: 70)
            .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(searchBook.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text(searchBook.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // 显示书源信息
                    Text("·")
                        .foregroundColor(.secondary)
                    
                    Text(searchBook.bookSourceName)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                if let intro = searchBook.intro {
                    Text(intro)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
