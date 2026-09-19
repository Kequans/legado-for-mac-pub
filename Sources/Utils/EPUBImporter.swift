import Foundation
import SwiftSoup

struct ImportedLocalBook {
    let title: String
    let author: String
    let chapters: [BookChapter]
    let sourceContent: String
}

enum EPUBImportError: Error, LocalizedError {
    case invalidArchive
    case missingContainer
    case missingPackage
    case noReadableChapters

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "EPUB 文件无法解压"
        case .missingContainer: return "EPUB 缺少 META-INF/container.xml"
        case .missingPackage: return "EPUB 缺少内容清单"
        case .noReadableChapters: return "EPUB 中没有可阅读的章节"
        }
    }
}

/// 使用 macOS 自带 unzip 读取 EPUB。这样 Package 不需要额外引入 ZIP 库，
/// 同时保留对标准 EPUB 2/3 container、OPF manifest 和 spine 的兼容。
final class EPUBImporter {
    static func importBook(from url: URL, bookUrl: String) throws -> ImportedLocalBook {
        let fileManager = Foundation.FileManager.default
        let extractionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LegadoEPUB-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractionDirectory) }

        guard archiveEntriesAreSafe(url: url), unzip(url: url, to: extractionDirectory) else {
            throw EPUBImportError.invalidArchive
        }

        let containerURL = extractionDirectory.appendingPathComponent("META-INF/container.xml")
        guard let containerXML = try? String(contentsOf: containerURL, encoding: .utf8) else {
            throw EPUBImportError.missingContainer
        }

        let containerDoc = try SwiftSoup.parse(containerXML, "", Parser.xmlParser())
        guard let packagePath = try containerDoc.select("rootfile").first()?.attr("full-path"),
              !packagePath.isEmpty else {
            throw EPUBImportError.missingPackage
        }

        let packageURL = extractionDirectory.appendingPathComponent(packagePath).standardizedFileURL
        guard isWithin(packageURL, directory: extractionDirectory) else {
            throw EPUBImportError.invalidArchive
        }
        guard let packageXML = try? String(contentsOf: packageURL, encoding: .utf8) else {
            throw EPUBImportError.missingPackage
        }
        let packageDoc = try SwiftSoup.parse(packageXML, "", Parser.xmlParser())

        let title = (try? packageDoc.select("dc|title").first()?.text()) ??
            (try? packageDoc.select("title").first()?.text()) ??
            url.deletingPathExtension().lastPathComponent
        let author = (try? packageDoc.select("dc|creator").first()?.text()) ??
            (try? packageDoc.select("creator").first()?.text()) ?? "本地文件"

        var manifest: [String: String] = [:]
        for item in try packageDoc.select("manifest item") {
            let id = try item.attr("id")
            let href = try item.attr("href")
            let mediaType = try item.attr("media-type")
            guard !id.isEmpty, !href.isEmpty else { continue }
            if mediaType.contains("html") || mediaType.contains("xhtml") || mediaType == "text/plain" {
                manifest[id] = href.removingPercentEncoding ?? href
            }
        }

        let packageDirectory = packageURL.deletingLastPathComponent()
        var chapters: [BookChapter] = []
        var sourceParts: [String] = []
        var sourceByteOffset = 0
        let itemRefs = try packageDoc.select("spine itemref")

        for (index, itemRef) in itemRefs.enumerated() {
            let idref = try itemRef.attr("idref")
            guard let href = manifest[idref] else { continue }
            let chapterURL = packageDirectory.appendingPathComponent(href).standardizedFileURL
            guard isWithin(chapterURL, directory: extractionDirectory) else { continue }
            guard let chapterHTML = try? String(contentsOf: chapterURL, encoding: .utf8) else { continue }

            let document = try SwiftSoup.parse(chapterHTML, chapterURL.absoluteString)
            let chapterTitle = (try? document.select("h1, h2, h3, title").first()?.text()) ?? "第 \(index + 1) 章"
            let body = try document.select("body").first()
            let content: String
            if let body {
                let paragraphElements = try body.select("p")
                let elements = paragraphElements.isEmpty ? try body.select("div") : paragraphElements
                let paragraphs = try elements.compactMap { element -> String? in
                    let value = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
                content = paragraphs.isEmpty ? try body.text() : paragraphs.joined(separator: "\n\n")
            } else {
                content = try document.text()
            }

            let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedContent.isEmpty else { continue }

            let separatorLength = sourceParts.isEmpty ? 0 : "\n\n".utf8.count
            let start = sourceByteOffset + separatorLength
            let end = start + cleanedContent.utf8.count
            var chapter = BookChapter(
                url: "\(bookUrl)#epub-\(index)",
                title: chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                bookUrl: bookUrl,
                index: chapters.count
            )
            chapter.start = Int64(start)
            chapter.end = Int64(end)
            sourceParts.append(cleanedContent)
            sourceByteOffset = end
            chapters.append(chapter)
        }

        guard !chapters.isEmpty else { throw EPUBImportError.noReadableChapters }
        return ImportedLocalBook(title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
                                 author: author.isEmpty ? "本地文件" : author,
                                 chapters: chapters,
                                 sourceContent: sourceParts.joined(separator: "\n\n"))
    }

    private static func unzip(url: URL, to directory: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", directory.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("EPUB 解压失败: \(error)")
            return false
        }
    }

    private static func archiveEntriesAreSafe(url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let listing = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
                return false
            }
            return listing.split(whereSeparator: \.isNewline).allSatisfy { entry in
                let path = String(entry)
                return !path.hasPrefix("/") &&
                    !path.split(separator: "/").contains("..")
            }
        } catch {
            return false
        }
    }

    private static func isWithin(_ file: URL, directory: URL) -> Bool {
        let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = file.resolvingSymlinksInPath().standardizedFileURL.path
        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }
}
