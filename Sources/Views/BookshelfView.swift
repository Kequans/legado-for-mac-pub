import SwiftUI

struct BookshelfView: View {
    @StateObject private var viewModel = BookshelfViewModel()
    @State private var selectedBook: Book?
    @State private var showImportBook = false
    @State private var gridLayout = true
    @State private var appConfig = MainAppConfig.load()
    @ObservedObject private var appState = AppState.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("书架")
                    .font(.title)
                    .bold()
                
                Spacer()
                
                Button(action: { gridLayout.toggle() }) {
                    Image(systemName: gridLayout ? "list.bullet" : "square.grid.2x2")
                }
                
                Button(action: { showImportBook = true }) {
                    Label("导入", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // 书籍列表
            if viewModel.books.isEmpty {
                emptyView
            } else {
                ScrollView {
                    if gridLayout {
                        gridView
                    } else {
                        listView
                    }
                }
            }
        }
        .sheet(isPresented: $showImportBook, onDismiss: {
            Task {
                await viewModel.loadBooks()
            }
        }) {
            ImportBookView()
        }
        .sheet(item: $selectedBook) { book in
            BookDetailView(book: book)
        }
        .task {
            await viewModel.loadBooks()
        }
        .onAppear {
            // 每次显示时重新加载配置
            appConfig = MainAppConfig.load()
        }
        .onChange(of: appState.isReading) { isReading in
            // 退出阅读时刷新书架
            if !isReading {
                Task {
                    await viewModel.loadBooks()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookshelfUpdated)) { _ in
            Task { await viewModel.loadBooks() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .databaseRestored)) { _ in
            Task { await viewModel.loadBooks() }
        }
    }
    
    // 网格视图
    private var gridView: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 20) {
            ForEach(viewModel.books.indices, id: \.self) { index in
                BookCoverCard(book: $viewModel.books[index])
                    .onTapGesture {
                        // 直接使用书架已经加载的数据，避免点击时同步查询数据库。
                        let book = viewModel.books[index]
                        if book.skipDetailPage {
                            viewModel.openBook(book)
                        } else {
                            selectedBook = book
                        }
                    }
                    .contextMenu {
                        Button("阅读") {
                            viewModel.openBook(viewModel.books[index])
                        }
                        Button("详情") {
                            selectedBook = viewModel.books[index]
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            viewModel.deleteBook(viewModel.books[index])
                        }
                    }
            }
        }
        .padding()
    }
    
    // 列表视图
    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.books.indices, id: \.self) { index in
                BookListRow(book: $viewModel.books[index])
                    .onTapGesture {
                        // 直接使用书架已经加载的数据，避免点击时同步查询数据库。
                        let book = viewModel.books[index]
                        if book.skipDetailPage {
                            viewModel.openBook(book)
                        } else {
                            selectedBook = book
                        }
                    }
                    .contextMenu {
                        Button("阅读") {
                            viewModel.openBook(viewModel.books[index])
                        }
                        Button("详情") {
                            selectedBook = viewModel.books[index]
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            viewModel.deleteBook(viewModel.books[index])
                        }
                    }
                Divider()
            }
        }
    }
    
    // 空视图
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("书架是空的")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Button("导入书籍") {
                showImportBook = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 书籍封面卡片
struct BookCoverCard: View {
    @Binding var book: Book
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面
            CachedCoverImage(book: $book, width: 120, height: 160)
                .cornerRadius(8)
                .shadow(radius: 2)
            
            // 书名
            Text(book.name)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
            
            // 作者
            Text(book.author)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
    }
}

// 书籍列表行
struct BookListRow: View {
    @Binding var book: Book
    
    var body: some View {
        HStack(spacing: 12) {
            // 封面
            CachedCoverImage(book: $book, width: 50, height: 70)
                .cornerRadius(4)
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.headline)
                
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let latestChapter = book.latestChapterTitle {
                    Text(latestChapter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 进度
            if book.totalChapterNum > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(book.durChapterIndex + 1)/\(book.totalChapterNum)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: Double(book.durChapterIndex + 1), total: Double(book.totalChapterNum))
                        .frame(width: 80)
                }
            }
        }
        .padding()
    }
}

// ViewModel
@MainActor
class BookshelfViewModel: ObservableObject {
    @Published var books: [Book] = []
    private let bookDAO = BookDAO()
    private var loadGeneration = 0
    
    func loadBooks() async {
        loadGeneration += 1
        let generation = loadGeneration
        let result = await Task.detached(priority: .userInitiated) { () -> Result<[Book], Error> in
            do {
                // 数据库读取放到后台，避免刷新书架时阻塞主线程交互。
                let loadedBooks = try BookDAO().getAll().sorted { $0.lastCheckTime > $1.lastCheckTime }
                return .success(loadedBooks)
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled, generation == loadGeneration else { return }

        switch result {
        case .success(let loadedBooks):
            books = loadedBooks
            print("📚 [BookshelfView] 加载了 \(books.count) 本书，按最近阅读时间排序")
        case .failure(let error):
            print("加载书籍失败: \(error)")
        }
    }
    
    func deleteBook(_ book: Book) {
        do {
            // 删除书籍及关联的章节数据
            try bookDAO.delete(bookUrl: book.bookUrl)
            try? BookChapterDAO().deleteChapters(bookUrl: book.bookUrl)
            try? ChapterContentDAO().deleteContents(bookUrl: book.bookUrl)
            try? ReadingDataDAO().deleteBookmarks(bookUrl: book.bookUrl)
            FileUtils.clearBookCache(bookUrl: book.bookUrl)
            books.removeAll { $0.id == book.id }
            print("✅ 已删除书籍及章节: \(book.name)")
        } catch {
            print("删除书籍失败: \(error)")
        }
    }
    
    func openBook(_ book: Book) {
        print("📂 [BookshelfView] 打开书籍 - 书名: \(book.name), 当前索引: \(book.durChapterIndex)")
        // 从数据库重新加载书籍以获取最新的阅读进度
        do {
            if var freshBook = try bookDAO.get(bookUrl: book.bookUrl) {
                // 更新lastCheckTime为当前时间，使其排到书架首位
                freshBook.lastCheckTime = Int64(Date().timeIntervalSince1970)
                try? bookDAO.save(freshBook)
                
                // 立即刷新书架排序
                Task {
                    await loadBooks()
                }
                
                print("✅ [BookshelfView] 从数据库加载书籍 - durChapterIndex: \(freshBook.durChapterIndex), skipDetailPage: \(freshBook.skipDetailPage)")
                AppState.shared.selectedBook = freshBook
                AppState.shared.isReading = true
            } else {
                print("⚠️ [BookshelfView] 数据库中找不到该书籍，使用传入的 book 对象")
                // 如果数据库中找不到该书籍，使用传入的 book 对象
                AppState.shared.selectedBook = book
                AppState.shared.isReading = true
            }
        } catch {
            print("❌ [BookshelfView] 加载书籍失败: \(error)")
            // 出错时使用传入的 book 对象
            AppState.shared.selectedBook = book
            AppState.shared.isReading = true
        }
    }
}

// 预览仅在 Xcode 中使用，CLI 构建移除
