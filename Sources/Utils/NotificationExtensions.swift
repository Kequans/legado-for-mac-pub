import Foundation

// 应用通知扩展
extension Notification.Name {
    static let bookSourceImported = Notification.Name("bookSourceImported")
    static let bookshelfUpdated = Notification.Name("bookshelfUpdated")
    static let databaseRestored = Notification.Name("databaseRestored")
}
