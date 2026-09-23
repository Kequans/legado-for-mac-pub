import Foundation

/// 顺序抓取分页列表，保留页面顺序、检测循环及重定向别名。
enum SourcePagination {
    static func collect<Item>(first: SourceRequest, limit: Int = 500,
                              fetch: (SourceRequest) async throws -> NetworkManager.Response,
                              parse: (NetworkManager.Response) throws -> ([Item], [SourceRequest])) async throws -> [Item] {
        var queue = [first]
        var queued: Set<String> = [identity(first)]
        var visited: Set<String> = []
        var output: [Item] = []
        var index = 0
        var fetched = 0
        while index < queue.count {
            try Task.checkCancellation()
            let request = queue[index]
            index += 1
            guard !visited.contains(identity(request)) else { continue }
            guard fetched < limit else { throw SourceRequestError.pageLimit(limit) }
            let response = try await fetch(request)
            try Task.checkCancellation()
            fetched += 1
            visited.insert(identity(request))
            let redirected = identity(request, url: response.url)
            if redirected != identity(request), visited.contains(redirected) { continue }
            visited.insert(redirected)
            let (items, next) = try parse(response)
            output.append(contentsOf: items)
            for page in next where !visited.contains(identity(page)) {
                if queued.insert(identity(page)).inserted {
                    guard queue.count < limit else { throw SourceRequestError.pageLimit(limit) }
                    queue.append(page)
                }
            }
        }
        return output
    }

    private static func identity(_ source: SourceRequest, url: URL? = nil) -> String {
        var components = URLComponents(url: url ?? source.request.url!, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        return (source.request.httpMethod ?? "GET") + " " + (components?.string ?? "") + " " +
            (source.request.httpBody?.base64EncodedString() ?? "")
    }
}
