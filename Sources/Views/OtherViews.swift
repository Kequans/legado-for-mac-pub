import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AboutView: View {
    @State private var showReleaseNotes = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                // Logo和标题
                VStack(spacing: 12) {
                    Image(systemName: "book.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)

                    Text("Legado for macOS")
                        .font(.title)
                        .bold()

                    Text("版本 \(AppReleaseInfo.currentVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        showReleaseNotes = true
                    } label: {
                        Label("更新日志", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 36)

                Divider()

                // 作者信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("作者")
                        .font(.headline)

                    Link(destination: URL(string: "https://github.com/Kequans")!) {
                        Label("Kequans", systemImage: "person.circle.fill")
                            .font(.body)
                    }
                    .foregroundColor(.primary)

                    Text("点个 Star 支持作者持续更新！")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Link(destination: URL(string: "https://github.com/Kequans/legado-for-mac-pub")!) {
                        Label("在 GitHub 点个 Star", systemImage: "star.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 520, alignment: .leading)

                Divider()

                // 项目信息
                VStack(alignment: .leading, spacing: 16) {
                    Text("项目信息")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("基于 Legado 开源阅读")
                                .font(.body)
                        }

                        Link(destination: URL(string: "https://github.com/gedoor/legado")!) {
                            HStack {
                                Image(systemName: "arrow.up.forward.circle")
                                Text("https://github.com/gedoor/legado")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.accentColor)
                            Text("项目仓库")
                                .font(.body)
                        }

                        Link(destination: URL(string: "https://github.com/Kequans/legado-for-mac-pub")!) {
                            HStack {
                                Image(systemName: "arrow.up.forward.circle")
                                Text("https://github.com/Kequans/legado-for-mac-pub")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showReleaseNotes) {
            ReleaseNotesView()
        }
    }
}

struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(AppReleaseInfo.notes) { note in
                        ReleaseNoteCard(note: note, isCurrent: note.version == AppReleaseInfo.currentVersion)
                    }
                }
                .padding(24)
            }
            .navigationTitle("更新日志")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 620, height: 620)
    }
}

private struct ReleaseNoteCard: View {
    let note: ReleaseNote
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("版本 \(note.version)")
                    .font(.title3)
                    .fontWeight(.semibold)
                if isCurrent {
                    Text("当前版本")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(note.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(note.title)
                .font(.headline)
            Text(note.summary)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(note.changes, id: \.self) { change in
                    Label(change, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DiscoverView: View {
    @State private var sources: [BookSource] = []
    @State private var selectedSource: BookSource?
    @State private var results: [SearchBook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("发现").font(.title).bold()
                Spacer()
                Picker("书源", selection: $selectedSource) {
                    Text("选择书源").tag(Optional<BookSource>.none)
                    ForEach(sources.filter { $0.enabled && $0.enabledExplore && $0.exploreUrl != nil }) { source in
                        Text(source.bookSourceName).tag(Optional(source))
                    }
                }
                .frame(width: 220)
                Button("刷新") { refresh() }
                    .disabled(selectedSource == nil || isLoading)
            }
            .padding()
            Divider()

            if isLoading {
                ProgressView("加载发现内容...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundColor(.secondary)
                    Text("选择一个启用发现功能的书源").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                CachedCoverImage(book: .constant(previewBook(for: result)), width: 110, height: 150)
                                Text(result.name).font(.headline).lineLimit(2)
                                Text(result.author).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { importResult(result) }
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            sources = (try? BookSourceDAO().getEnabled()) ?? []
            if selectedSource == nil { selectedSource = sources.first(where: { $0.enabledExplore && $0.exploreUrl != nil }) }
        }
    }

    private func refresh() {
        guard let source = selectedSource else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await BookSourceEngine.shared.explore(bookSource: source)
                await MainActor.run {
                    results = fetched
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func previewBook(for result: SearchBook) -> Book {
        var book = Book(bookUrl: result.bookUrl, name: result.name, author: result.author)
        book.coverUrl = result.coverUrl
        return book
    }

    private func importResult(_ result: SearchBook) {
        guard let source = selectedSource else { return }
        Task {
            do {
                var book = try await BookSourceEngine.shared.getBookInfo(bookUrl: result.bookUrl, bookSource: source, variable: result.variable)
                BookSourceEngine.shared.mergeSearchResult(result, into: &book, bookSource: source)
                guard !book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BookSourceError.parseError
                }
                try BookDAO().save(book)
                if let chapters = try? await BookSourceEngine.shared.getChapterList(book: book, bookSource: source) {
                    book.totalChapterNum = chapters.count
                    try BookDAO().save(book)
                    try BookChapterDAO().saveAll(chapters)
                }
                await MainActor.run { results.removeAll { $0.id == result.id } }
            } catch {
                await MainActor.run { errorMessage = "导入失败: \(error.localizedDescription)" }
            }
        }
    }
}

struct RSSView: View {
    var body: some View {
        RSSSourceManagementView()
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text("设置")
                    .font(.title2)
                    .bold()

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // 标签页选择器
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    Text("通用")
                        .font(.system(size: 14))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(selectedTab == 0 ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: { selectedTab = 1 }) {
                    Text("网络")
                        .font(.system(size: 14))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(selectedTab == 1 ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 内容区域
            Group {
                if selectedTab == 0 {
                    GeneralSettingsView()
                } else {
                    NetworkSettingsView()
                }
            }
        }
        .frame(width: 550, height: 450)
    }
}

struct GeneralSettingsView: View {
    @State private var preloadCountText: String
    @State private var showError = false
    @State private var errorMessage = ""

    init() {
        let loadedConfig = MainAppConfig.load()
        _preloadCountText = State(initialValue: String(loadedConfig.preloadChapterCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 阅读缓存
                VStack(alignment: .leading, spacing: 12) {
                    Text("阅读缓存")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Text("预加载章节数:")
                            .frame(width: 110, alignment: .leading)

                        TextField("", text: $preloadCountText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit {
                                savePreloadCount()
                            }

                        Text("章")
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    Text("范围: 10-50章，预加载后续章节以加快阅读速度")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(showError ? .red : .green)
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

                Divider()

                // 数据管理
                VStack(alignment: .leading, spacing: 12) {
                    Text("数据")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button("备份数据") {
                            exportBackup()
                        }

                        Button("恢复数据") {
                            importBackup()
                        }

                        Button("替换规则") {
                            showReplaceRules = true
                        }

                        Button("阅读历史") {
                            showHistory = true
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .sheet(isPresented: $showReplaceRules) {
            ReplaceRulesView()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
        .onDisappear {
            savePreloadCount()
        }
    }

    @State private var showReplaceRules = false
    @State private var showHistory = false

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "备份 Legado 数据"
        panel.nameFieldStringValue = "Legado备份_\(Date().formatted(date: .numeric, time: .omitted)).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try BackupService.shared.export(to: url)
                errorMessage = "备份已保存到 \(url.lastPathComponent)"
                showError = false
            } catch {
                errorMessage = "备份失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "恢复 Legado 数据"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try BackupService.shared.restore(from: url)
                NotificationCenter.default.post(name: .databaseRestored, object: nil)
                errorMessage = "数据恢复成功"
                showError = false
            } catch {
                errorMessage = "恢复失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func savePreloadCount() {
        guard let count = Int(preloadCountText) else {
            showError = true
            errorMessage = "请输入有效的数字"
            // 恢复为当前配置值
            preloadCountText = String(MainAppConfig.load().preloadChapterCount)
            return
        }

        if count < 10 || count > 50 {
            showError = true
            errorMessage = "数值必须在 10-50 之间"
            preloadCountText = String(MainAppConfig.load().preloadChapterCount)
            return
        }

        showError = false
        var newConfig = MainAppConfig.load()
        newConfig.preloadChapterCount = count
        newConfig.save()
        print("✅ 预加载章节数已设置为: \(count)")
    }
}

struct NetworkSettingsView: View {
    @State private var userAgent = ReadConfig.shared.userAgent
    @State private var timeoutText = String(Int(ReadConfig.shared.requestTimeout))
    @State private var enableProxy = AppConfig.shared.enableProxy
    @State private var proxyHost = AppConfig.shared.proxyHost
    @State private var proxyPortText = AppConfig.shared.proxyPort == 0 ? "" : String(AppConfig.shared.proxyPort)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 网络请求
                VStack(alignment: .leading, spacing: 12) {
                    Text("网络请求")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("User-Agent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: $userAgent)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveNetworkSettings() }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("超时时间(秒)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: $timeoutText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .onSubmit { saveNetworkSettings() }
                    }
                }

                Divider()

                // 代理设置
                VStack(alignment: .leading, spacing: 12) {
                    Text("代理设置")
                        .font(.headline)

                    Toggle("启用代理", isOn: $enableProxy)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("代理地址")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: $proxyHost)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("代理端口")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("", text: $proxyPortText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .onDisappear {
            saveNetworkSettings()
        }
    }

    private func saveNetworkSettings() {
        let timeout = max(5, min(300, Double(timeoutText) ?? ReadConfig.shared.requestTimeout))
        ReadConfig.shared.userAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ReadConfig.shared.userAgent
            : userAgent
        ReadConfig.shared.requestTimeout = timeout
        AppConfig.shared.enableProxy = enableProxy
        AppConfig.shared.proxyHost = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.shared.proxyPort = Int(proxyPortText) ?? 0
        timeoutText = String(Int(timeout))
        NetworkManager.shared.reloadConfiguration()
    }
}

struct ReplaceRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [ReplaceRule] = []
    @State private var name = ""
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var isRegex = true

    private let dao = ReadingDataDAO()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if rules.isEmpty {
                    Text("还没有替换规则")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(rules) { rule in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { rule.enabled },
                                    set: { enabled in update(rule, enabled: enabled) }
                                ))
                                .labelsHidden()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.name).font(.headline)
                                    Text("\(rule.pattern) → \(rule.replacement)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    delete(rule)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Divider()
                Form {
                    Section("添加规则") {
                        TextField("名称", text: $name)
                        TextField("匹配内容或正则", text: $pattern)
                        TextField("替换为", text: $replacement)
                        Toggle("使用正则表达式", isOn: $isRegex)
                        HStack {
                            Spacer()
                            Button("添加") { addRule() }
                                .buttonStyle(.borderedProminent)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || pattern.isEmpty)
                        }
                    }
                }
                .frame(height: 190)
            }
            .navigationTitle("替换规则")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 620, height: 620)
        .task { loadRules() }
    }

    private func loadRules() {
        rules = (try? dao.getReplaceRules()) ?? []
    }

    private func addRule() {
        var rule = ReplaceRule(name: name, pattern: pattern, replacement: replacement)
        rule.isRegex = isRegex
        rule.order = rules.count
        do {
            try dao.saveReplaceRule(rule)
            rules.insert(rule, at: 0)
            name = ""
            pattern = ""
            replacement = ""
        } catch {
            print("保存替换规则失败: \(error)")
        }
    }

    private func update(_ rule: ReplaceRule, enabled: Bool) {
        var updated = rule
        updated.enabled = enabled
        try? dao.saveReplaceRule(updated)
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = updated
        }
    }

    private func delete(_ rule: ReplaceRule) {
        try? dao.deleteReplaceRule(id: rule.id)
        rules.removeAll { $0.id == rule.id }
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [ReadRecord] = []
    private let dao = ReadingDataDAO()

    var body: some View {
        NavigationView {
            Group {
                if records.isEmpty {
                    Text("还没有阅读记录")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.bookName).font(.headline)
                                Text(Date(timeIntervalSince1970: TimeInterval(record.time)).formatted())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(formatDuration(record.readTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("阅读历史")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 500, height: 500)
        .task { records = (try? dao.getReadRecords()) ?? [] }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        if seconds < 60 { return "阅读 \(seconds) 秒" }
        if seconds < 3600 { return "阅读 \(seconds / 60) 分钟" }
        return "阅读 \(seconds / 3600) 小时"
    }
}

struct BookSourceEditView: View {
    let bookSource: BookSource?
    @Environment(\.dismiss) var dismiss
    @State private var draft: BookSource
    @State private var group = ""
    @State private var urlPattern = ""
    @State private var header = ""
    @State private var searchUrl = ""
    @State private var exploreUrl = ""
    @State private var searchRuleJSON = ""
    @State private var bookInfoRuleJSON = ""
    @State private var tocRuleJSON = ""
    @State private var contentRuleJSON = ""
    @State private var errorMessage: String?

    init(bookSource: BookSource?) {
        self.bookSource = bookSource
        let source = bookSource ?? BookSource(bookSourceUrl: "https://", bookSourceName: "新书源")
        _draft = State(initialValue: source)
        _group = State(initialValue: source.bookSourceGroup ?? "")
        _urlPattern = State(initialValue: source.bookUrlPattern ?? "")
        _header = State(initialValue: source.header ?? "")
        _searchUrl = State(initialValue: source.searchUrl ?? "")
        _exploreUrl = State(initialValue: source.exploreUrl ?? "")
        _searchRuleJSON = State(initialValue: Self.encodeRule(source.ruleSearch))
        _bookInfoRuleJSON = State(initialValue: Self.encodeRule(source.ruleBookInfo))
        _tocRuleJSON = State(initialValue: Self.encodeRule(source.ruleToc))
        _contentRuleJSON = State(initialValue: Self.encodeRule(source.ruleContent))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(bookSource == nil ? "添加书源" : "编辑书源")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()

            Form {
                Section("基本信息") {
                    TextField("书源名称", text: $draft.bookSourceName)
                    TextField("书源地址", text: $draft.bookSourceUrl)
                    TextField("分组", text: $group)
                    TextField("书籍 URL 正则", text: $urlPattern)
                    Toggle("启用书源", isOn: $draft.enabled)
                    Toggle("启用发现", isOn: $draft.enabledExplore)
                }

                Section("搜索与发现") {
                    TextField("搜索地址", text: $searchUrl)
                    TextField("发现地址", text: $exploreUrl)
                    TextEditor(text: $header)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60)
                        .overlay(alignment: .topLeading) {
                            if header.isEmpty {
                                Text("请求头 JSON 或每行一个 Header: Value")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("规则 JSON") {
                    RuleEditorField(title: "搜索规则", text: $searchRuleJSON)
                    RuleEditorField(title: "书籍信息规则", text: $bookInfoRuleJSON)
                    RuleEditorField(title: "目录规则", text: $tocRuleJSON)
                    RuleEditorField(title: "正文规则", text: $contentRuleJSON)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
        .frame(width: 760, height: 720)
    }

    private func save() {
        guard !draft.bookSourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "书源名称和地址不能为空"
            return
        }

        draft.bookSourceGroup = group.isEmpty ? nil : group
        draft.bookUrlPattern = urlPattern.isEmpty ? nil : urlPattern
        draft.header = header.isEmpty ? nil : header
        draft.searchUrl = searchUrl.isEmpty ? nil : searchUrl
        draft.exploreUrl = exploreUrl.isEmpty ? nil : exploreUrl

        do {
            draft.ruleSearch = try Self.decodeRule(searchRuleJSON)
            draft.ruleBookInfo = try Self.decodeRule(bookInfoRuleJSON)
            draft.ruleToc = try Self.decodeRule(tocRuleJSON)
            draft.ruleContent = try Self.decodeRule(contentRuleJSON)
            try BookSourceDAO().save(draft)
            NotificationCenter.default.post(name: .bookSourceImported, object: nil)
            dismiss()
        } catch {
            errorMessage = "规则 JSON 无效: \(error.localizedDescription)"
        }
    }

    private static func encodeRule<T: Encodable>(_ rule: T?) -> String {
        guard let rule, let data = try? JSONEncoder().encode(rule),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private static func decodeRule<T: Decodable>(_ text: String) throws -> T? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { throw DatabaseError.invalidData }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct RuleEditorField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 70)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25)))
        }
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
