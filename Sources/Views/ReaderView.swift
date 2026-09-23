import SwiftUI
import AppKit

// PreferenceKey for scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// PreferenceKey for content height
struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// 窗口查找辅助器
struct HostingWindowFinder: NSViewRepresentable {
    var callback: (NSWindow?) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.callback(nsView.window)
        }
    }
}

struct ReaderView: View {
    let book: Book
    @StateObject private var viewModel: ReaderViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var showBookDetail = false
    @State private var showSourceSwitcher = false
    @State private var fontSizeInputText = ""
    @FocusState private var isFontSizeInputFocused: Bool
    @State private var chapterJumpInput = ""
    @FocusState private var isChapterJumpInputFocused: Bool
    @State private var pendingChapterIndex: Int?
    @State private var hostingWindow: NSWindow?
    @State private var windowUpdateTimer: Timer?
    @State private var scrollViewID = UUID()  // 用于重置ScrollView
    
    init(book: Book) {
        self.book = book
        _viewModel = StateObject(wrappedValue: ReaderViewModel(book: book))
    }
    
    var body: some View {
        ZStack {
            // 背景色
            viewModel.backgroundColor
                .ignoresSafeArea()
            
            ZStack(alignment: .top) {
                // 阅读内容区域（自适应高度）
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // 滚动位置锚点（放在最顶部）
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .global).minY
                                )
                            }
                            .frame(height: 0)
                            .id("scrollAnchor_0")
                            
                            // 章节标题
                            Text(viewModel.currentChapter?.title ?? "")
                                .font(.title2)
                                .bold()
                                .padding(.top)
                                .id("chapterTop")
                            
                            // 正文内容
                            Text(viewModel.content)
                                .font(.system(size: viewModel.fontSize))
                                .lineSpacing(viewModel.lineSpacing)
                                .foregroundColor(viewModel.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    GeometryReader { contentGeo in
                                        Color.clear.preference(
                                            key: ContentHeightPreferenceKey.self,
                                            value: contentGeo.size.height
                                        )
                                    }
                                )
                                .id("content")
                        }
                        .padding()
                        .frame(width: viewModel.pageWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { topY in
                        let offset = max(0, -topY)
                        viewModel.currentScrollOffset = offset
                    }
                    .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                        viewModel.contentHeight = height
                        
                        // 内容加载完成后恢复滚动位置
                        if viewModel.shouldRestoreScroll && viewModel.savedScrollPosition > 0 && height > 100 {
                            let percentage = viewModel.savedScrollPosition / 10000.0
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if reduceMotion {
                                    proxy.scrollTo("content", anchor: UnitPoint(x: 0, y: percentage))
                                } else {
                                    withAnimation(.easeOut(duration: 0.22)) {
                                        proxy.scrollTo("content", anchor: UnitPoint(x: 0, y: percentage))
                                    }
                                }
                                viewModel.shouldRestoreScroll = false
                                print("📍 [ReaderView] 恢复滚动到 \(Int(percentage * 100))%")
                            }
                        }
                    }
                    .id(scrollViewID)
                    .onTapGesture {
                        toggleToolbar()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.showToolbar {
                    VStack(spacing: 0) {
                        topToolbar
                        Spacer(minLength: 0)
                        bottomToolbar
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(reduceMotion ? .identity : .opacity)
                    .zIndex(1)
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.18),
                value: viewModel.showToolbar
            )
            
            // 隐藏的窗口查找器
            HostingWindowFinder { window in
                self.hostingWindow = window
            }
            .frame(width: 0, height: 0)
        }
        .sheet(isPresented: $showChapterList) {
            ChapterListView(
                chapters: viewModel.nearbyChapters,
                startIndex: viewModel.chapterWindowStartIndex,
                currentIndex: viewModel.currentChapterIndex
            ) { index in
                Task {
                    await viewModel.loadChapter(at: index)
                }
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkListView(
                bookmarks: viewModel.bookmarks,
                currentIndex: viewModel.currentChapterIndex,
                onSelect: { bookmark in
                    showBookmarks = false
                    Task { await viewModel.loadChapter(at: bookmark.chapterIndex) }
                },
                onDelete: { bookmark in
                    viewModel.deleteBookmark(bookmark)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showBookDetail) {
            BookDetailView(book: book, hideActions: true)
        }
        .sheet(isPresented: $showSourceSwitcher) {
            SourceSwitcherView(book: book, viewModel: viewModel)
        }
        .task {
            await viewModel.initialize()
        }
        .onAppear {
            chapterJumpInput = "\(viewModel.currentChapterIndex + 1)"
        }
        .onDisappear {
            // 窗口关闭时保存阅读进度（包括滚动位置）
            viewModel.saveProgress()
        }
        .onChange(of: viewModel.pageWidth) { _ in
            updateWindowSize()
        }
        .onChange(of: viewModel.pageHeight) { _ in
            updateWindowSize()
        }
        .onChange(of: viewModel.currentChapterIndex) { _ in
            // 切换章节时标记需要恢复位置
            viewModel.shouldRestoreScroll = true
            scrollViewID = UUID()  // 重置ScrollView以触发滚动
            if !isChapterJumpInputFocused {
                chapterJumpInput = "\(viewModel.currentChapterIndex + 1)"
            }
        }
    }

    private func toggleToolbar() {
        if reduceMotion {
            viewModel.showToolbar.toggle()
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.showToolbar.toggle()
            }
        }
    }
    
    // 顶部工具栏
    private var topToolbar: some View {
        HStack {
            Button("关闭") {
                dismiss()
            }
            
            Spacer()
            
            // 书名和书源信息
            VStack(spacing: 2) {
                Text(book.name)
                    .font(.headline)
                
                // 显示书源信息，可点击换源
                Button(action: { showSourceSwitcher = true }) {
                    HStack(spacing: 4) {
                        Text(book.originName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("点击换源")
            }
            
            Spacer()
            
            Button(action: { showBookDetail = true }) {
                Image(systemName: "info.circle")
            }

            Button(action: {
                viewModel.addBookmarkFromCurrentChapter()
                showBookmarks = true
            }) {
                Image(systemName: "bookmark")
            }
            .help("添加书签")

            Button(action: { showBookmarks = true }) {
                Image(systemName: "bookmark.fill")
            }
            .help("查看书签")
            
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // 底部工具栏
    private var bottomToolbar: some View {
        let windowStart = viewModel.chapterWindowStartIndex
        let windowEnd = viewModel.chapterWindowEndIndex
        let windowLength = max(0, windowEnd - windowStart)

        let toolbar = VStack(spacing: 12) {
            // 只显示当前章节附近的导航窗口，避免把整本书的章节数量和范围交给 Slider。
            HStack {
                Text("第 \(viewModel.currentChapterIndex + 1) 章")
                    .font(.caption)
                
                if windowLength > 0 {
                    Slider(
                        value: Binding(
                            get: {
                                let selectedIndex = pendingChapterIndex ?? viewModel.currentChapterIndex
                                return Double(min(max(selectedIndex, windowStart), windowEnd) - windowStart)
                            },
                            set: { newValue in
                                pendingChapterIndex = windowStart + Int(newValue.rounded())
                            }
                        ),
                        in: 0...Double(windowLength),
                        step: 1,
                        onEditingChanged: { isEditing in
                            guard !isEditing, let targetIndex = pendingChapterIndex else { return }
                            pendingChapterIndex = nil
                            Task {
                                await viewModel.loadChapter(at: targetIndex)
                            }
                        }
                    )
                } else {
                    Spacer()
                }

                Text("附近 \(windowStart + 1)-\(windowEnd + 1)章")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(viewModel.currentChapter?.title ?? "")
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
            }
            
            // 按钮组
            HStack(spacing: 40) {
                Button(action: { Task { await viewModel.previousChapter() } }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                .disabled(viewModel.currentChapterIndex == 0)
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Button(action: { showChapterList = true }) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                }
                .help("查看当前章节附近的目录")

                HStack(spacing: 4) {
                    TextField("章节", text: $chapterJumpInput)
                        .frame(width: 54)
                        .textFieldStyle(.roundedBorder)
                        .focused($isChapterJumpInputFocused)
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .onSubmit {
                            jumpToChapter()
                        }

                    Button("跳转") {
                        jumpToChapter()
                    }
                    .buttonStyle(.bordered)
                    .help("输入章节号后跳转")
                }
                
                // 字体大小快捷调整
                HStack(spacing: 8) {
                    Button(action: { viewModel.decreaseFontSize() }) {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .help("减小字号 (Cmd+-)")
                    .keyboardShortcut("-", modifiers: .command)
                    
                    TextField("字号", text: $fontSizeInputText)
                        .frame(width: 35)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFontSizeInputFocused)
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .onSubmit {
                            if let size = Int(fontSizeInputText) {
                                viewModel.setFontSize(CGFloat(size))
                            }
                            fontSizeInputText = "\(Int(viewModel.fontSize))"
                            isFontSizeInputFocused = false
                        }
                        .onTapGesture {
                            if !isFontSizeInputFocused {
                                fontSizeInputText = "\(Int(viewModel.fontSize))"
                                isFontSizeInputFocused = true
                            }
                        }
                    
                    Button(action: { viewModel.increaseFontSize() }) {
                        Image(systemName: "textformat.size.larger")
                    }
                    .help("增大字号 (Cmd++)")
                    .keyboardShortcut("+", modifiers: .command)
                }
                .onChange(of: viewModel.fontSize) { newSize in
                    if !isFontSizeInputFocused {
                        fontSizeInputText = "\(Int(newSize))"
                    }
                }
                .onAppear {
                    fontSizeInputText = "\(Int(viewModel.fontSize))"
                }
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                
                Button(action: { Task { await viewModel.nextChapter() } }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
                .disabled(viewModel.currentChapterIndex >= viewModel.chapters.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
        return toolbar
            .padding()
            .background(.ultraThinMaterial)
    }

    private func jumpToChapter() {
        guard let chapterNumber = Int(chapterJumpInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              chapterNumber >= 1,
              chapterNumber <= viewModel.chapters.count else {
            chapterJumpInput = "\(viewModel.currentChapterIndex + 1)"
            isChapterJumpInputFocused = false
            return
        }

        chapterJumpInput = "\(chapterNumber)"
        isChapterJumpInputFocused = false
        pendingChapterIndex = nil
        Task {
            await viewModel.loadChapter(at: chapterNumber - 1)
        }
    }
    
    // 更新窗口大小以匹配内容
    private func updateWindowSize(animated: Bool = true) {
        guard let window = hostingWindow else { return }
        
        DispatchQueue.main.async {
            // 计算需要的窗口尺寸（始终预留工具栏空间）
            let toolbarHeight: CGFloat = 200  // 固定预留工具栏空间
            let titleBarHeight: CGFloat = 28
            
            let targetWidth = viewModel.pageWidth
            let targetHeight = viewModel.pageHeight + toolbarHeight + titleBarHeight
            
            let newSize = NSSize(width: targetWidth, height: targetHeight)
            let currentFrame = window.frame
            
            // 保持左上角位置不变（macOS坐标系中左下角）
            let newOriginX = currentFrame.origin.x
            let newOriginY = currentFrame.origin.y + (currentFrame.height - newSize.height)
            
            let newFrame = NSRect(
                x: newOriginX,
                y: newOriginY,
                width: newSize.width,
                height: newSize.height
            )
            
            // 根据参数决定是否动画
            let shouldAnimate = animated && !showSettings
            window.setFrame(newFrame, display: true, animate: shouldAnimate)
        }
    }
}

// 章节列表视图
struct ChapterListView: View {
    let chapters: [BookChapter]
    let startIndex: Int
    let currentIndex: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List(chapters.indices, id: \.self) { offset in
                let index = startIndex + offset
                Button(action: {
                    onSelect(index)
                    dismiss()
                }) {
                    HStack {
                        Text(chapters[offset].title)
                            .foregroundColor(index == currentIndex ? .accentColor : .primary)
                        
                        Spacer()
                        
                        if index == currentIndex {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("附近章节")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

struct BookmarkListView: View {
    let bookmarks: [Bookmark]
    let currentIndex: Int
    let onSelect: (Bookmark) -> Void
    let onDelete: (Bookmark) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("还没有书签")
                            .foregroundColor(.secondary)
                        Text("点击阅读器工具栏的书签按钮添加当前章节")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                onSelect(bookmark)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(bookmark.chapterName)
                                            .font(.headline)
                                        if bookmark.chapterIndex == currentIndex {
                                            Image(systemName: "book.fill")
                                                .font(.caption)
                                                .foregroundColor(.accentColor)
                                        }
                                        Spacer()
                                        Text(Date(timeIntervalSince1970: TimeInterval(bookmark.time)).relativeDescription)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(bookmark.bookText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    onDelete(bookmark)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets where index < bookmarks.count {
                                onDelete(bookmarks[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 450, minHeight: 420)
    }
}

// 阅读设置视图
struct ReaderSettingsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) var dismiss
    @State private var widthText = ""
    @State private var heightText = ""
    @State private var fontSizeText = ""
    @State private var lineSpacingText = ""
    @State private var isRecordingPrevious = false
    @State private var isRecordingNext = false
    @FocusState private var isWidthFocused: Bool
    @FocusState private var isHeightFocused: Bool
    @FocusState private var isFontSizeFocused: Bool
    @FocusState private var isLineSpacingFocused: Bool
    
    var body: some View {
        Form {
            // 页面布局设置
            GroupBox(label: Label("页面布局", systemImage: "rectangle.portrait")) {
                VStack(alignment: .leading, spacing: 16) {
                    // 页面宽度
                    HStack(spacing: 12) {
                        Text("宽度")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)
                        
                        Button(action: { viewModel.decreasePageWidth() }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("减小宽度 (Cmd+[)")
                        
                        TextField("", text: $widthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced))
                            .focused($isWidthFocused)
                            .onSubmit {
                                if let newWidth = Double(widthText) {
                                    viewModel.setPageWidth(newWidth)
                                }
                                widthText = "\(Int(viewModel.pageWidth))"
                            }
                            .onTapGesture {
                                if !isWidthFocused {
                                    isWidthFocused = true
                                    widthText = ""
                                }
                            }
                        
                        Button(action: { viewModel.increasePageWidth() }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("增大宽度 (Cmd+])")
                        
                        Text("像素")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        
                        Spacer()
                        
                        Text("范围: 600-1400")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 窗口高度
                    HStack(spacing: 12) {
                        Text("高度")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)
                        
                        Button(action: { viewModel.decreasePageHeight() }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("减小高度")
                        
                        TextField("", text: $heightText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced))
                            .focused($isHeightFocused)
                            .onSubmit {
                                if let newHeight = Double(heightText) {
                                    viewModel.setPageHeight(newHeight)
                                }
                                heightText = "\(Int(viewModel.pageHeight))"
                            }
                            .onTapGesture {
                                if !isHeightFocused {
                                    isHeightFocused = true
                                    heightText = ""
                                }
                            }
                        
                        Button(action: { viewModel.increasePageHeight() }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("增大高度")
                        
                        Text("像素")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        
                        Spacer()
                        
                        Text("范围: 400-1200")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("💡 窗口高度控制可见区域，内容可滚动查看")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(12)
            }
            
            // 字体设置
            GroupBox(label: Label("字体", systemImage: "textformat.size")) {
                VStack(alignment: .leading, spacing: 16) {
                    // 字号
                    HStack(spacing: 12) {
                        Text("字号")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)
                        
                        Button(action: { viewModel.decreaseFontSize() }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("减小字号 (Cmd+-)")
                        
                        TextField("", text: $fontSizeText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced))
                            .focused($isFontSizeFocused)
                            .onSubmit {
                                if let newSize = Double(fontSizeText) {
                                    viewModel.setFontSize(CGFloat(newSize))
                                }
                                fontSizeText = "\(Int(viewModel.fontSize))"
                            }
                            .onTapGesture {
                                if !isFontSizeFocused {
                                    isFontSizeFocused = true
                                    fontSizeText = ""
                                }
                            }
                        
                        Button(action: { viewModel.increaseFontSize() }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("增大字号 (Cmd++)")
                        
                        Text("pt")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        
                        Spacer()
                        
                        Text("范围: 12-32")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 行距
                    HStack(spacing: 12) {
                        Text("行距")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)
                        
                        Button(action: { 
                            if viewModel.lineSpacing > 0 {
                                viewModel.lineSpacing -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("减小行距")
                        
                        TextField("", text: $lineSpacingText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced))
                            .focused($isLineSpacingFocused)
                            .onSubmit {
                                if let newSpacing = Double(lineSpacingText) {
                                    viewModel.lineSpacing = CGFloat(max(0, min(20, newSpacing)))
                                }
                                lineSpacingText = "\(Int(viewModel.lineSpacing))"
                            }
                            .onTapGesture {
                                if !isLineSpacingFocused {
                                    isLineSpacingFocused = true
                                    lineSpacingText = ""
                                }
                            }
                        
                        Button(action: { 
                            if viewModel.lineSpacing < 20 {
                                viewModel.lineSpacing += 1
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("增大行距")
                        
                        Text("pt")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        
                        Spacer()
                        
                        Text("范围: 0-20")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }
            
            // 颜色设置
            GroupBox(label: Label("颜色", systemImage: "paintpalette")) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("背景色")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)
                        ColorPicker("", selection: $viewModel.backgroundColor)
                            .labelsHidden()
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("文字色")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)
                        ColorPicker("", selection: $viewModel.textColor)
                            .labelsHidden()
                        Spacer()
                    }
                }
                .padding(12)
            }

            // 快捷键设置
            GroupBox(label: Label("快捷键", systemImage: "keyboard")) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("上一章")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)

                        Text(shortcutDisplayText(viewModel.previousChapterShortcut))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)

                        Button(isRecordingPrevious ? "按下按键..." : "录制") {
                            isRecordingPrevious = true
                            recordShortcut(for: .previous)
                        }
                        .disabled(isRecordingPrevious || isRecordingNext)

                        Button("重置") {
                            viewModel.previousChapterShortcut = .leftArrow
                        }
                        .disabled(viewModel.previousChapterShortcut == .leftArrow)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("下一章")
                            .frame(width: 60, alignment: .leading)
                            .font(.body)

                        Text(shortcutDisplayText(viewModel.nextChapterShortcut))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)

                        Button(isRecordingNext ? "按下按键..." : "录制") {
                            isRecordingNext = true
                            recordShortcut(for: .next)
                        }
                        .disabled(isRecordingPrevious || isRecordingNext)

                        Button("重置") {
                            viewModel.nextChapterShortcut = .rightArrow
                        }
                        .disabled(viewModel.nextChapterShortcut == .rightArrow)

                        Spacer()
                    }
                }
                .padding(12)
            }
        }
        .padding()
        .frame(width: 520, height: 680)
        .navigationTitle("阅读设置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .onAppear {
            widthText = "\(Int(viewModel.pageWidth))"
            heightText = "\(Int(viewModel.pageHeight))"
            fontSizeText = "\(Int(viewModel.fontSize))"
            lineSpacingText = "\(Int(viewModel.lineSpacing))"
        }
        .onChange(of: viewModel.pageWidth) { _ in
            if !isWidthFocused {
                widthText = "\(Int(viewModel.pageWidth))"
            }
        }
        .onChange(of: viewModel.pageHeight) { _ in
            if !isHeightFocused {
                heightText = "\(Int(viewModel.pageHeight))"
            }
        }
        .onChange(of: viewModel.fontSize) { _ in
            if !isFontSizeFocused {
                fontSizeText = "\(Int(viewModel.fontSize))"
            }
        }
        .onChange(of: viewModel.lineSpacing) { _ in
            if !isLineSpacingFocused {
                lineSpacingText = "\(Int(viewModel.lineSpacing))"
            }
        }
    }

    private func shortcutDisplayText(_ shortcut: KeyboardShortcut) -> String {
        var parts: [String] = []

        for modifier in shortcut.modifiers {
            switch modifier {
            case "command": parts.append("⌘")
            case "option": parts.append("⌥")
            case "control": parts.append("⌃")
            case "shift": parts.append("⇧")
            default: break
            }
        }

        switch shortcut.key {
        case "leftArrow": parts.append("←")
        case "rightArrow": parts.append("→")
        case "upArrow": parts.append("↑")
        case "downArrow": parts.append("↓")
        case "pageUp": parts.append("Page Up")
        case "pageDown": parts.append("Page Down")
        case "space": parts.append("Space")
        case "return": parts.append("Return")
        case "escape": parts.append("Esc")
        default: parts.append(shortcut.key.uppercased())
        }

        return parts.joined(separator: " ")
    }

    enum ShortcutTarget {
        case previous
        case next
    }

    private func recordShortcut(for target: ShortcutTarget) {
        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode

            var modifierStrings: [String] = []
            if modifiers.contains(.command) { modifierStrings.append("command") }
            if modifiers.contains(.option) { modifierStrings.append("option") }
            if modifiers.contains(.control) { modifierStrings.append("control") }
            if modifiers.contains(.shift) { modifierStrings.append("shift") }

            let keyString = self.keyCodeToString(keyCode)
            let newShortcut = KeyboardShortcut(key: keyString, modifiers: modifierStrings)

            // 移除监听器
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }

            // 更新快捷键
            DispatchQueue.main.async {
                switch target {
                case .previous:
                    if newShortcut != self.viewModel.nextChapterShortcut {
                        self.viewModel.previousChapterShortcut = newShortcut
                    }
                    self.isRecordingPrevious = false
                case .next:
                    if newShortcut != self.viewModel.previousChapterShortcut {
                        self.viewModel.nextChapterShortcut = newShortcut
                    }
                    self.isRecordingNext = false
                }
            }

            return nil
        }
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 123: return "leftArrow"
        case 124: return "rightArrow"
        case 126: return "upArrow"
        case 125: return "downArrow"
        case 116: return "pageUp"
        case 121: return "pageDown"
        case 49: return "space"
        case 36: return "return"
        case 53: return "escape"
        default:
            if keyCode <= 25 {
                let char = Character(UnicodeScalar(keyCode + 97)!)
                return String(char)
            }
            return "unknown"
        }
    }
}

// ViewModel

// ViewModel
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var chapters: [BookChapter] = []
    @Published var bookmarks: [Bookmark] = []
    @Published var currentChapterIndex: Int = 0
    @Published var currentChapter: BookChapter?
    @Published var content: String = "正在加载..."
    @Published var showToolbar: Bool = true {
        didSet { saveConfig() }
    }

    /// 目录弹层和底部 Slider 只展示当前章节附近的窗口，完整章节数组仅用于索引和精确跳转。
    var chapterWindowStartIndex: Int {
        guard !chapters.isEmpty else { return 0 }
        let safeIndex = min(max(currentChapterIndex, 0), chapters.count - 1)
        return max(0, safeIndex - 10)
    }

    var chapterWindowEndIndex: Int {
        guard !chapters.isEmpty else { return 0 }
        let safeIndex = min(max(currentChapterIndex, 0), chapters.count - 1)
        return min(chapters.count - 1, safeIndex + 10)
    }

    var nearbyChapters: [BookChapter] {
        guard !chapters.isEmpty else { return [] }
        return Array(chapters[chapterWindowStartIndex...chapterWindowEndIndex])
    }
    
    // 阅读设置
    @Published var pageWidth: CGFloat = 900 {
        didSet { saveConfig() }
    }
    @Published var pageHeight: CGFloat = 800 {
        didSet { saveConfig() }
    }
    @Published var fontSize: CGFloat = 18 {
        didSet { saveConfig() }
    }
    @Published var lineSpacing: CGFloat = 8 {
        didSet { saveConfig() }
    }
    @Published var backgroundColor: Color = .white {
        didSet { saveConfig() }
    }
    @Published var textColor: Color = .black {
        didSet { saveConfig() }
    }
    @Published var previousChapterShortcut: KeyboardShortcut = .leftArrow {
        didSet {
            saveConfig()
            setupKeyboardShortcuts()
        }
    }
    @Published var nextChapterShortcut: KeyboardShortcut = .rightArrow {
        didSet {
            saveConfig()
            setupKeyboardShortcuts()
        }
    }

    // 滚动位置
    @Published var savedScrollPosition: CGFloat = 0  // 保存的滚动百分比（0-10000）
    var shouldRestoreScroll: Bool = false  // 是否需要恢复滚动位置
    var currentScrollOffset: CGFloat = 0  // 当前滚动偏移量
    var contentHeight: CGFloat = 0  // 内容高度

    private var book: Book
    private let bookSourceDAO = BookSourceDAO()
    private let bookChapterDAO = BookChapterDAO()
    private let bookDAO = BookDAO()
    private let chapterContentDAO = ChapterContentDAO()
    private let readingDataDAO = ReadingDataDAO()
    private var isLoadingConfig = false  // 防止加载配置时触发保存
    private var preloadTask: Task<Void, Never>?  // 预加载任务
    private var lastPreloadStartIndex: Int = -1  // 上次预加载的起始章节索引
    private var keyboardMonitor: Any?  // 快捷键监听器
    private let sessionStartedAt = Date()
    
    init(book: Book) {
        self.book = book
        self.currentChapterIndex = book.durChapterIndex
        self.savedScrollPosition = CGFloat(book.durChapterPos)
        self.shouldRestoreScroll = (book.durChapterPos > 0)
        print("📖 [ReaderView] 初始化 - book.durChapterIndex: \(book.durChapterIndex), durChapterPos: \(book.durChapterPos), 书名: \(book.name)")
        loadConfig()
        setupKeyboardShortcuts()
    }
    
    func initialize() async {
        print("📖 [ReaderView] 开始初始化")
        loadBookmarks()

        // 优先使用已经保存的目录，打开阅读器时不必重复请求网络；目录为空时再刷新。
        if book.isLocal {
            _ = await loadChaptersFromNetwork()
        } else {
            chapters = (try? bookChapterDAO.getChapters(bookUrl: book.bookUrl)) ?? []
            if chapters.isEmpty {
                _ = await loadChaptersFromNetwork()
            }
        }
        
        // 确保索引有效
        if !chapters.isEmpty && currentChapterIndex >= chapters.count {
            currentChapterIndex = max(0, min(currentChapterIndex, chapters.count - 1))
        }
        
        // 加载当前章节
        if !chapters.isEmpty {
            await loadChapter(at: currentChapterIndex)
        } else {
            content = "暂无章节"
        }
    }
    
    @discardableResult
    func loadChaptersFromNetwork() async -> Bool {
        // 本地书籍从数据库加载章节
        if book.isLocal {
            print("📚 本地书籍，从数据库加载章节列表 - 书名: \(book.name)")
            do {
                let cachedChapters = try bookChapterDAO.getChapters(bookUrl: book.bookUrl)
                if !cachedChapters.isEmpty {
                    chapters = cachedChapters
                    print("✅ 从数据库加载了 \(chapters.count) 个章节")
                    return true
                } else {
                    print("❌ 数据库中没有章节")
                    return false
                }
            } catch {
                print("❌ 从数据库加载章节失败: \(error)")
                return false
            }
        }

        print("🔄 开始从网络加载章节列表 - 书名: \(book.name)")
        do {
            if let bookSource = try bookSourceDAO.get(bookSourceUrl: book.origin) {
                let fetchedChapters = try await BookSourceEngine.shared.getChapterList(book: book, bookSource: bookSource)
                print("📦 获取到 \(fetchedChapters.count) 个章节")

                // 保存到数据库
                try bookChapterDAO.saveAll(fetchedChapters)
                chapters = fetchedChapters
                print("✅ 章节列表已保存到数据库")

                // 更新书籍章节数
                var updatedBook = book
                updatedBook.totalChapterNum = chapters.count
                try bookDAO.save(updatedBook)
                return true
            } else {
                print("❌ 找不到书源: \(book.origin)")
                // 尝试从数据库加载章节
                let cachedChapters = try bookChapterDAO.getChapters(bookUrl: book.bookUrl)
                if !cachedChapters.isEmpty {
                    chapters = cachedChapters
                    print("📦 从数据库加载了 \(chapters.count) 个章节")
                    return true
                } else {
                    print("❌ 数据库中也没有章节")
                    return false
                }
            }
        } catch {
            print("❌ 加载章节列表失败: \(error)")
            // 尝试从数据库加载章节
            do {
                let cachedChapters = try bookChapterDAO.getChapters(bookUrl: book.bookUrl)
                if !cachedChapters.isEmpty {
                    chapters = cachedChapters
                    print("📦 从数据库加载了 \(chapters.count) 个章节")
                    return true
                } else {
                    print("❌ 数据库中也没有章节")
                    return false
                }
            } catch {
                print("❌ 从数据库加载章节也失败: \(error)")
                return false
            }
        }
    }
    
    func loadChapter(at index: Int) async {
        guard index >= 0 && index < chapters.count else { 
            content = "章节索引越界"
            return 
        }
        
        currentChapterIndex = index
        currentChapter = chapters[index]
        content = "正在加载..."
        
        // 如果是切换到不同章节，重置滚动位置；如果是同一章节，保持当前位置
        if index != book.durChapterIndex || savedScrollPosition == 0 {
            savedScrollPosition = 0
        }
        
        // 加载章节内容
        if book.isLocal {
            if let localContent = currentChapter.flatMap({
                FileUtils.readLocalChapterContent(bookUrl: book.bookUrl, chapter: $0)
            }) {
                content = localContent.isEmpty ? "章节内容为空" : applyReplaceRules(to: localContent)
                print("📖 从本地章节源文件读取: \(currentChapter?.title ?? "未知章节")")
            } else {
                content = "无法读取本地章节内容"
            }
        } else {
            // 先尝试从缓存加载
            await loadChapterFromCacheOrNetwork()
            
            // 触发预加载（仅在需要时）
            await preloadNextChaptersIfNeeded()
        }
    }
    
    /// 从缓存或网络加载章节
    private func loadChapterFromCacheOrNetwork() async {
        guard let chapter = currentChapter else { return }
        
        do {
            // 先尝试从缓存加载
            if let cached = try chapterContentDAO.get(chapterUrl: chapter.url) {
                content = applyReplaceRules(to: cached.content)
                print("📦 从缓存加载章节: \(chapter.title)")
                return
            }
            
            // 缓存未命中，从网络加载
            await loadChapterFromNetwork()
        } catch {
            print("加载章节失败: \(error)")
            await loadChapterFromNetwork()
        }
    }
    
    @discardableResult
    func loadChapterFromNetwork() async -> Bool {
        guard let chapter = currentChapter else { return false }

        do {
            if let bookSource = try bookSourceDAO.get(bookSourceUrl: book.origin) {
                let fetchedContent = try await BookSourceEngine.shared.getChapterContent(chapter: chapter, bookSource: bookSource)
                content = applyReplaceRules(to: fetchedContent)

                // 保存到缓存
                let chapterContent = ChapterContent(
                    chapterUrl: chapter.url,
                    bookUrl: book.bookUrl,
                    content: fetchedContent
                )
                try? chapterContentDAO.save(chapterContent)
                print("💾 章节已缓存: \(chapter.title)")
                return true
            } else {
                print("❌ 找不到书源: \(book.origin)")
                content = "找不到书源"
                return false
            }
        } catch {
            print("加载章节内容失败: \(error)")
            content = "加载失败: \(error.localizedDescription)"
            return false
        }
    }
    
    /// 检查是否需要预加载
    private func preloadNextChaptersIfNeeded() async {
        let config = MainAppConfig.load()
        let preloadCount = config.preloadChapterCount
        
        // 首次预加载或已经阅读完上次预加载的范围
        let shouldPreload = lastPreloadStartIndex < 0 || 
                           currentChapterIndex >= lastPreloadStartIndex + preloadCount
        
        if shouldPreload {
            lastPreloadStartIndex = currentChapterIndex
            await preloadNextChapters()
        } else {
            print("⏸️ 无需预加载：当前第\(currentChapterIndex + 1)章，上次预加载范围：\(lastPreloadStartIndex + 1)-\(lastPreloadStartIndex + preloadCount)章")
        }
    }
    
    /// 预加载后续章节
    private func preloadNextChapters() async {
        // 取消之前的预加载任务
        preloadTask?.cancel()
        
        // 创建新的预加载任务
        preloadTask = Task {
            let config = MainAppConfig.load()
            let preloadCount = config.preloadChapterCount
            
            guard let bookSource = try? bookSourceDAO.get(bookSourceUrl: book.origin) else {
                return
            }
            
            // 计算实际可预加载的章节数（不超过剩余章节）
            let remainingChapters = chapters.count - currentChapterIndex - 1
            let actualPreloadCount = min(preloadCount, remainingChapters)
            
            if actualPreloadCount <= 0 {
                print("📚 已是最后一章，无需预加载")
                return
            }
            
            print("🔄 开始预加载后续 \(actualPreloadCount) 章（剩余 \(remainingChapters) 章）")
            
            for offset in 1...actualPreloadCount {
                // 检查任务是否被取消
                if Task.isCancelled { break }
                
                let nextIndex = currentChapterIndex + offset
                guard nextIndex < chapters.count else { break }
                
                let chapter = chapters[nextIndex]
                
                // 检查是否已缓存
                if let isCached = try? chapterContentDAO.isCached(chapterUrl: chapter.url),
                   isCached {
                    print("⏭️ 章节已缓存，跳过: \(chapter.title)")
                    continue
                }
                
                // 从网络加载并缓存
                do {
                    let fetchedContent = try await BookSourceEngine.shared.getChapterContent(
                        chapter: chapter,
                        bookSource: bookSource
                    )
                    
                    let chapterContent = ChapterContent(
                        chapterUrl: chapter.url,
                        bookUrl: book.bookUrl,
                        content: fetchedContent
                    )
                    try? chapterContentDAO.save(chapterContent)
                    print("✅ 预加载完成: \(chapter.title)")
                    
                    // 添加小延迟避免请求过快
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                } catch {
                    print("⚠️ 预加载失败: \(chapter.title) - \(error)")
                }
            }
            
            if !Task.isCancelled {
                print("🎉 预加载完成")
            }
        }
    }
    
    func previousChapter() async {
        if currentChapterIndex > 0 {
            await loadChapter(at: currentChapterIndex - 1)
        }
    }
    
    func nextChapter() async {
        if currentChapterIndex < chapters.count - 1 {
            await loadChapter(at: currentChapterIndex + 1)
        }
    }
    
    func saveProgress() {
        // 计算滚动百分比
        if contentHeight > 0 {
            let scrollPercentage = (currentScrollOffset / contentHeight) * 10000
            savedScrollPosition = max(0, min(10000, scrollPercentage))
            print("📊 [ReaderView] 滚动数据 - 偏移: \(Int(currentScrollOffset)), 内容高度: \(Int(contentHeight)), 百分比: \(Int(savedScrollPosition)/100)%")
        }
        
        var updatedBook = book
        updatedBook.durChapterIndex = currentChapterIndex
        updatedBook.durChapterTitle = currentChapter?.title
        updatedBook.durChapterTime = Int64(Date().timeIntervalSince1970)
        updatedBook.durChapterPos = Int(savedScrollPosition)
        
        print("💾 [ReaderView] 保存进度 - 章节索引: \(currentChapterIndex), 滚动位置: \(Int(savedScrollPosition)), 章节标题: \(currentChapter?.title ?? "未知"), 书名: \(book.name)")
        
        do {
            try bookDAO.save(updatedBook)
            book = updatedBook
            let elapsed = max(1, Int64(Date().timeIntervalSince(sessionStartedAt)))
            try? readingDataDAO.saveReadRecord(ReadRecord(bookName: book.name, readTime: elapsed))
            print("✅ [ReaderView] 进度保存成功")
        } catch {
            print("❌ [ReaderView] 保存进度失败: \(error)")
        }
    }

    func loadBookmarks() {
        bookmarks = (try? readingDataDAO.getBookmarks(bookUrl: book.bookUrl)) ?? []
    }

    func addBookmarkFromCurrentChapter() {
        guard let chapter = currentChapter else { return }
        let excerpt = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = Bookmark(
            bookUrl: book.bookUrl,
            bookName: book.name,
            chapterIndex: currentChapterIndex,
            chapterPos: Int(savedScrollPosition),
            chapterName: chapter.title,
            bookText: String(excerpt.prefix(120)),
            content: content
        )
        do {
            try readingDataDAO.saveBookmark(bookmark)
            bookmarks.insert(bookmark, at: 0)
        } catch {
            print("❌ 保存书签失败: \(error)")
        }
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        do {
            try readingDataDAO.deleteBookmark(id: bookmark.id)
            bookmarks.removeAll { $0.id == bookmark.id }
        } catch {
            print("❌ 删除书签失败: \(error)")
        }
    }

    private func applyReplaceRules(to value: String) -> String {
        readingDataDAO.applyReplaceRules(to: value, bookUrl: book.bookUrl)
    }
    
    // 字体大小调整方法
    func increaseFontSize() {
        if fontSize < 32 {
            fontSize += 1
        }
    }
    
    func decreaseFontSize() {
        if fontSize > 12 {
            fontSize -= 1
        }
    }
    
    func setFontSize(_ size: CGFloat) {
        fontSize = max(12, min(32, size))
    }
    
    // 页面宽度调整方法
    func increasePageWidth() {
        if pageWidth < 1400 {
            pageWidth += 50
        }
    }
    
    func decreasePageWidth() {
        if pageWidth > 600 {
            pageWidth -= 50
        }
    }
    
    func setPageWidth(_ width: Double) {
        pageWidth = CGFloat(max(600, min(1400, width)))
    }
    
    // 页面高度调整方法
    func increasePageHeight() {
        if pageHeight < 1200 {
            pageHeight += 50
        }
    }
    
    func decreasePageHeight() {
        if pageHeight > 400 {
            pageHeight -= 50
        }
    }
    
    func setPageHeight(_ height: Double) {
        pageHeight = CGFloat(max(300, min(1200, height)))
    }
    
    /// 换源后重新加载
    func reloadWithNewSource(_ newBook: Book) async {
        // 更新book引用
        let oldIndex = currentChapterIndex
        
        // 重新初始化
        book = newBook
        currentChapterIndex = newBook.durChapterIndex
        savedScrollPosition = CGFloat(newBook.durChapterPos)
        
        // 清空章节缓存并重新加载
        chapters = []
        
        do {
            // 加载章节列表
            chapters = try bookChapterDAO.getChapters(bookUrl: newBook.bookUrl)
            
            if chapters.isEmpty {
                // 从网络获取新书源的章节
                await loadChaptersFromNetwork()
            }
            
            // 加载当前章节
            if !chapters.isEmpty {
                // 尽量恢复到相同章节
                let targetIndex = min(oldIndex, chapters.count - 1)
                await loadChapter(at: targetIndex)
                print("✅ 换源成功，加载到第 \(targetIndex + 1) 章")
            } else {
                content = "新书源暂无章节"
            }
        } catch {
            print("❌ 换源后加载失败: \(error)")
            content = "换源后加载失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 配置管理
    
    /// 加载配置
    private func loadConfig() {
        isLoadingConfig = true
        let config = ReaderConfig.load()

        pageWidth = config.pageWidth
        pageHeight = config.pageHeight
        fontSize = config.fontSize
        lineSpacing = config.lineSpacing
        backgroundColor = config.getBackgroundColor()
        textColor = config.getTextColor()
        showToolbar = config.showToolbar
        previousChapterShortcut = config.previousChapterShortcut
        nextChapterShortcut = config.nextChapterShortcut

        isLoadingConfig = false
        print("已加载阅读器配置")
    }

    /// 保存配置
    private func saveConfig() {
        guard !isLoadingConfig else { return }  // 加载配置时不保存

        let config = ReaderConfig(
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            backgroundColor: ReaderConfig.colorToHex(backgroundColor),
            textColor: ReaderConfig.colorToHex(textColor),
            showToolbar: showToolbar,
            previousChapterShortcut: previousChapterShortcut,
            nextChapterShortcut: nextChapterShortcut
        )
        config.save()
    }

    // MARK: - 快捷键管理

    private func setupKeyboardShortcuts() {
        removeKeyboardShortcuts()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode

            if self.matchesShortcut(keyCode: keyCode, modifiers: modifiers, shortcut: self.previousChapterShortcut) {
                Task { @MainActor in
                    await self.previousChapter()
                }
                return nil
            }

            if self.matchesShortcut(keyCode: keyCode, modifiers: modifiers, shortcut: self.nextChapterShortcut) {
                Task { @MainActor in
                    await self.nextChapter()
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyboardShortcuts() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    deinit {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
        }
        preloadTask?.cancel()
    }

    private func matchesShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, shortcut: KeyboardShortcut) -> Bool {
        let keyMatches = keyCodeMatches(keyCode, key: shortcut.key)
        let modifiersMatch = modifiersMatch(modifiers, expected: shortcut.modifiers)
        return keyMatches && modifiersMatch
    }

    private func keyCodeMatches(_ keyCode: UInt16, key: String) -> Bool {
        switch key {
        case "leftArrow": return keyCode == 123
        case "rightArrow": return keyCode == 124
        case "upArrow": return keyCode == 126
        case "downArrow": return keyCode == 125
        case "pageUp": return keyCode == 116
        case "pageDown": return keyCode == 121
        case "space": return keyCode == 49
        case "return": return keyCode == 36
        case "escape": return keyCode == 53
        default:
            if key.count == 1, let char = key.lowercased().first {
                let charCode = Int(char.asciiValue ?? 0)
                if charCode >= 97 && charCode <= 122 {
                    let expectedKeyCode = UInt16(charCode - 97)
                    return keyCode == expectedKeyCode
                }
            }
            return false
        }
    }

    private func modifiersMatch(_ actual: NSEvent.ModifierFlags, expected: [String]) -> Bool {
        var expectedFlags: NSEvent.ModifierFlags = []
        for modifier in expected {
            switch modifier {
            case "command": expectedFlags.insert(.command)
            case "option": expectedFlags.insert(.option)
            case "control": expectedFlags.insert(.control)
            case "shift": expectedFlags.insert(.shift)
            default: break
            }
        }

        let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return actual.intersection(relevantFlags) == expectedFlags
    }
}

// MARK: - 换源视图
struct SourceSwitcherView: View {
    let book: Book
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) var dismiss
    @State private var searchResults: [SearchBook] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var isRefreshing = false  // 是否正在刷新当前书源
    @State private var searchTask: Task<Void, Never>?  // 搜索任务

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("换源")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("取消") {
                    // 取消搜索任务
                    searchTask?.cancel()
                    dismiss()
                }
            }
            .padding()

            Divider()

            // 当前书源
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("当前书源")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        Task {
                            await refreshCurrentSource()
                        }
                    }) {
                        Label("刷新本书源", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(isRefreshing || isSearching)
                }
                .padding(.horizontal)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.originName)
                            .font(.subheadline)
                            .bold()
                        Text(book.origin)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            .padding(.vertical)

            Divider()

            // 搜索结果
            if isSearching && searchResults.isEmpty {
                ProgressView("正在搜索其他书源...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !isSearching {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("未找到其他可用书源")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(searchResults) { result in
                                SourceResultRow(searchBook: result, currentSource: book.origin) {
                                    searchTask?.cancel()
                                    Task {
                                        await switchToSource(result)
                                    }
                                }
                            }
                        }
                        .padding()
                    }

                    // 底部搜索状态
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
        .frame(width: 500, height: 600)
        .onAppear {
            // 打开对话框时自动开始搜索
            searchTask = Task {
                await performSearch()
            }
        }
        .onDisappear {
            // 关闭对话框时取消搜索
            searchTask?.cancel()
        }
    }
    
    private func performSearch() async {
        isSearching = true
        searchResults = []
        errorMessage = nil

        let keyword = book.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            errorMessage = "当前书籍缺少书名，无法搜索其它书源"
            isSearching = false
            return
        }

        do {
            let bookSourceDAO = BookSourceDAO()
            let sources = try bookSourceDAO.getEnabled()

            guard sources.count > 1 else {
                errorMessage = "没有其他可用书源"
                isSearching = false
                return
            }

            print("🔍 开始搜索其他书源，书名: \(book.name)")

            let otherSources = sources.filter { $0.bookSourceUrl != book.origin }
            let maxConcurrent = min(6, otherSources.count)
            await withTaskGroup(of: (Int, [SearchBook]).self) { group in
                var nextSourceIndex = 0
                var activeTasks = 0

                while activeTasks < maxConcurrent, nextSourceIndex < otherSources.count {
                    let source = otherSources[nextSourceIndex]
                    let sourceIndex = nextSourceIndex
                    nextSourceIndex += 1
                    activeTasks += 1

                    group.addTask {
                        do {
                            let results = try await BookSourceEngine.shared.search(
                                keyword: keyword,
                                bookSource: source
                            )
                            let exactMatches = results.filter {
                                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == keyword.lowercased()
                            }
                            if !exactMatches.isEmpty {
                                print("✅ 书源【\(source.bookSourceName)】找到 \(exactMatches.count) 个完全匹配")
                            }
                            return (sourceIndex, exactMatches)
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

                    if !results.isEmpty {
                        await MainActor.run {
                            searchResults.append(contentsOf: results)
                            searchResults.sort { $0.bookSourceName < $1.bookSourceName }
                        }
                    }

                    if nextSourceIndex < otherSources.count && !Task.isCancelled {
                        let source = otherSources[nextSourceIndex]
                        let sourceIndex = nextSourceIndex
                        nextSourceIndex += 1
                        activeTasks += 1

                        group.addTask {
                            do {
                                let results = try await BookSourceEngine.shared.search(
                                    keyword: keyword,
                                    bookSource: source
                                )
                                let exactMatches = results.filter {
                                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == keyword.lowercased()
                                }
                                if !exactMatches.isEmpty {
                                    print("✅ 书源【\(source.bookSourceName)】找到 \(exactMatches.count) 个完全匹配")
                                }
                                return (sourceIndex, exactMatches)
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
                print("⏹️ 搜索已取消")
                return
            }

            print("🔄 搜索完成，共找到 \(searchResults.count) 个可换源")

            if searchResults.isEmpty {
                errorMessage = "未找到完全匹配的书源"
            }
        } catch {
            errorMessage = "搜索失败: \(error.localizedDescription)"
            print("搜索失败: \(error)")
        }

        isSearching = false
    }

    private func refreshCurrentSource() async {
        // 取消正在进行的搜索
        searchTask?.cancel()

        isRefreshing = true
        isSearching = false
        errorMessage = nil

        print("🔄 开始刷新当前书源...")

        // 重新加载章节列表
        let chaptersSuccess = await viewModel.loadChaptersFromNetwork()

        if !chaptersSuccess {
            errorMessage = "刷新失败：无法加载章节列表"
            isRefreshing = false
            return
        }

        // 重新加载当前章节内容
        let contentSuccess = await viewModel.loadChapterFromNetwork()

        if !contentSuccess {
            errorMessage = "刷新失败：无法加载章节内容"
            isRefreshing = false
            return
        }

        print("✅ 刷新完成")

        isRefreshing = false

        await MainActor.run {
            dismiss()
        }
    }

    private func switchToSource(_ newSource: SearchBook) async {
        isSearching = true
        
        do {
            // 获取新书源的完整信息
            let bookSourceDAO = BookSourceDAO()
            guard let bookSource = try bookSourceDAO.get(bookSourceUrl: newSource.bookSourceUrl) else {
                errorMessage = "找不到对应的书源"
                isSearching = false
                return
            }
            
            // 获取书籍详情
            let engine = BookSourceEngine.shared
            var newBook = try await engine.getBookInfo(bookUrl: newSource.bookUrl, bookSource: bookSource, variable: newSource.variable)
            engine.mergeSearchResult(newSource, into: &newBook, bookSource: bookSource)

            guard !newBook.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookSourceError.parseError
            }
            
            // 保留原有的阅读进度
            newBook.durChapterIndex = book.durChapterIndex
            newBook.durChapterPos = book.durChapterPos
            newBook.durChapterTime = book.durChapterTime
            
            // 更新书籍信息
            let bookDAO = BookDAO()
            try bookDAO.save(newBook)
            
            // 重新加载章节
            await viewModel.reloadWithNewSource(newBook)
            
            print("✅ 成功切换到书源: \(newSource.bookSourceName)")
            
            await MainActor.run {
                dismiss()
            }
        } catch {
            errorMessage = "换源失败: \(error.localizedDescription)"
            print("❌ 换源失败: \(error)")
        }
        
        isSearching = false
    }
}

// MARK: - 换源结果行
struct SourceResultRow: View {
    let searchBook: SearchBook
    let currentSource: String
    let onSwitch: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(searchBook.bookSourceName)
                    .font(.subheadline)
                    .bold()
                Text(searchBook.bookSourceUrl)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let latest = searchBook.latestChapterTitle {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("最新")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(latest)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
            }
            
            Button("换源") {
                onSwitch()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
