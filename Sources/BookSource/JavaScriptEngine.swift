import Foundation
import JavaScriptCore
import CryptoKit

/// JavaScript执行引擎，用于支持书源中的JS规则
class JavaScriptEngine {
    @TaskLocal static var current: JavaScriptEngine?
    static var shared: JavaScriptEngine { current ?? JavaScriptEngine() }

    static func withScope<T>(seed: String? = nil, bindings: [String: Any] = [:],
                             network: NetworkManager = .shared, headers: [String: String] = [:],
                             operation: () async throws -> T) async rethrows -> T {
        let engine = JavaScriptEngine()
        if let seed, let data = seed.data(using: .utf8),
           let values = try? JSONDecoder().decode([String: String].self, from: data) { engine.cache = values }
        engine.bindings = bindings
        engine.network = network
        engine.requestHeaders = headers
        return try await $current.withValue(engine, operation: operation)
    }

    func putVariable(_ key: String, value: String) { cache[key] = value }
    func getVariable(_ key: String) -> String { cache[key] ?? "" }

    var savedVariables: String? {
        guard let data = try? JSONEncoder().encode(cache) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private var bindings: [String: Any] = [:]
    private var network: NetworkManager = .shared
    private var requestHeaders: [String: String] = [:]
    
    private var context: JSContext
    private var cache: [String: String] = [:] // 全局缓存，用于java.put/get
    
    private init() {
        self.context = JSContext()!
        setupEnvironment()
    }
    
    /// 设置JavaScript执行环境
    private func setupEnvironment() {
        // 设置异常处理
        context.exceptionHandler = { context, exception in
            if let error = exception?.toString() {
                print("JavaScript执行错误: \(error)")
            }
        }
        
        // 注入常用的Java对象模拟
        setupJavaObjects()
        
        // 注入常用的工具函数
        setupUtilFunctions()
        
        // 注入网络请求函数
        setupNetworkFunctions()
    }
    
    /// 设置Java对象模拟（阅读APP中的Java对象）
    private func setupJavaObjects() {
        // java对象命名空间
        context.evaluateScript("""
        var java = {
            ajax: function(url) {
                return _fetch(url);
            },
            ajaxAll: function(urls) {
                return _fetchAll(urls);
            },
            connect: function(url) {
                return _fetch(url);
            },
            put: function(key, value) {
                _putCache(key, value);
                return value;
            },
            get: function(key) {
                return _getCache(key);
            },
            getString: function(key) {
                return _getCache(key) || "";
            },
            remove: function(key) {
                return _removeCache(key);
            }
        };
        """)
    }
    
    /// 设置工具函数
    private func setupUtilFunctions() {
        // Base64编码
        let base64Encode: @convention(block) (String) -> String = { text in
            return text.data(using: .utf8)?.base64EncodedString() ?? ""
        }
        context.setObject(base64Encode, forKeyedSubscript: "base64Encode" as NSString)
        
        // Base64解码
        let base64Decode: @convention(block) (String) -> String = { encoded in
            guard let data = Data(base64Encoded: encoded),
                  let decoded = String(data: data, encoding: .utf8) else {
                return ""
            }
            return decoded
        }
        context.setObject(base64Decode, forKeyedSubscript: "base64Decode" as NSString)
        
        // MD5
        let md5: @convention(block) (String) -> String = { text in
            // 简化版MD5，实际应该使用CryptoKit
            return text.md5Hash()
        }
        context.setObject(md5, forKeyedSubscript: "md5" as NSString)

        // Android Legado exposes these helpers through java as well as globally.
        context.evaluateScript("""
        java.md5Encode = md5;
        java.md5Encode16 = function(value) { return md5(value).substring(8, 24); };
        java.base64Encode = base64Encode;
        java.base64Decode = base64Decode;
        java.timeFormat = function(ms) {
            var d = new Date(Number(ms));
            function pad(n) { return ('0' + n).slice(-2); }
            return d.getFullYear() + '-' + pad(d.getMonth()+1) + '-' + pad(d.getDate()) +
                ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
        };
        """)

    }

    /// 设置网络请求函数
    private func setupNetworkFunctions() {
        let fetch: @convention(block) (String) -> JSValue = { [weak self] url in
            guard let self else { return JSValue() }
            do { return self.makeResponse(try self.fetchSynchronously([url]).first ?? "") }
            catch {
                self.context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: self.context)
                return JSValue(undefinedIn: self.context)
            }
        }
        context.setObject(fetch, forKeyedSubscript: "_fetch" as NSString)
        let fetchAll: @convention(block) (JSValue) -> JSValue = { [weak self] urls in
            guard let self else { return JSValue() }
            do {
                return JSValue(object: try self.fetchSynchronously(urls.toArray() as? [String] ?? []).map(self.makeResponse), in: self.context)
            } catch {
                self.context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: self.context)
                return JSValue(undefinedIn: self.context)
            }
        }
        context.setObject(fetchAll, forKeyedSubscript: "_fetchAll" as NSString)

        // _putCache - 使用self.cache
        let putCache: @convention(block) (String, String) -> Void = { [weak self] key, value in
            self?.cache[key] = value
            print("💾 保存到缓存: \(key) = \(value)")
        }
        context.setObject(putCache, forKeyedSubscript: "_putCache" as NSString)
        
        // _getCache - 先从当前variables查找，再从self.cache查找
        let getCache: @convention(block) (String) -> String? = { [weak self] key in
            guard let self = self else { return nil }

            // 1. 先尝试从当前evaluate()的variables中获取
            if let currentVars = self.context.objectForKeyedSubscript("_currentVariables"),
               !currentVars.isUndefined,
               let value = currentVars.objectForKeyedSubscript(key as NSString),
               !value.isUndefined && !value.isNull {
                let stringValue = value.toString()
                print("💾 从variables读取: \(key) = \(stringValue ?? "nil")")
                return stringValue
            }

            // 2. 再从全局cache中获取
            let value = self.cache[key]
            print("💾 从缓存读取: \(key) = \(value ?? "nil")")
            return value
        }
        context.setObject(getCache, forKeyedSubscript: "_getCache" as NSString)

        let removeCache: @convention(block) (String) -> String? = { [weak self] key in
            self?.cache.removeValue(forKey: key)
        }
        context.setObject(removeCache, forKeyedSubscript: "_removeCache" as NSString)
    }
    
    private func makeResponse(_ text: String) -> JSValue {
        let object = JSValue(newObjectIn: context)!
        let body: @convention(block) () -> String = { text }
        object.setObject(body, forKeyedSubscript: "body" as NSString)
        object.setObject(body, forKeyedSubscript: "toString" as NSString)
        return object
    }

    private final class FetchResult: @unchecked Sendable {
        let lock = NSLock()
        private var result: Result<[String], Error>?
        func set(_ value: Result<[String], Error>) { lock.lock(); defer { lock.unlock() }; result = value }
        func get() -> Result<[String], Error>? { lock.lock(); defer { lock.unlock() }; return result }
    }

    private func fetchSynchronously(_ urls: [String]) throws -> [String] {
        try Task.checkCancellation()
        let box = FetchResult()
        let base = context.objectForKeyedSubscript("baseUrl")?.toString() ?? ""
        let requests = try urls.map { try SourceRequest.parse($0, baseURL: base.isEmpty ? $0 : base, headers: requestHeaders) }
        let network = self.network
        let signal = DispatchSemaphore(value: 0)
        // 不继承解析器的 JSContext；工作任务只返回 Swift 值。
        let task = Task.detached {
            do {
                var values: [String] = []
                for request in requests {
                    try Task.checkCancellation()
                    values.append(try await network.fetch(request).text)
                }
                box.set(.success(values))
            } catch { box.set(.failure(error)) }
            signal.signal()
        }
        let deadline = Date().addingTimeInterval(120)
        while signal.wait(timeout: .now() + 0.05) == .timedOut {
            if Task.isCancelled { task.cancel(); throw CancellationError() }
            if Date() >= deadline { task.cancel(); throw URLError(.timedOut) }
        }
        try Task.checkCancellation()
        return try box.get()!.get()
    }

    /// 执行JavaScript代码
    /// - Parameters:
    ///   - script: JS代码
    ///   - variables: 注入的变量（如baseUrl, result等）
    ///   - jsLib: 书源自定义JS库代码
    /// - Returns: 执行结果
    func evaluate(_ script: String, variables: [String: Any] = [:], jsLib: String? = nil) throws -> JSValue {
        try Task.checkCancellation()
        if script.contains("JavaImporter") || script.contains("Packages.") || script.contains("importClass(") {
            throw BookSourceError.unsupportedJavaScriptInRule
        }
        let variables = bindings.merging(variables) { _, new in new }
        // 每个解析操作使用独立 JSContext；put/get 通过模型 variable 跨阶段传递。
        let localContext = self.context

        // JSContext 会保留上一次异常；每次执行前清理，避免把旧错误误判为本次错误。
        localContext.exception = nil
        
        // 如果有jsLib，先执行它
        if let jsLib = jsLib, !jsLib.isEmpty {
            localContext.evaluateScript(jsLib)
        }
        
        // 预处理JS代码，转换不支持的语法
        let processedScript = preprocessScript(script)
        
        // 包装JS代码在函数作用域中，并确保返回最后的表达式
        let wrappedScript = """
        (function() {
            \(processedScript)
        })()
        """
        
        // 将variables存储到_currentVariables，供java.get()访问
        let varsObject = localContext.objectForKeyedSubscript("Object").invokeMethod("create", withArguments: [NSNull()])!
        for (key, value) in variables {
            varsObject.setObject(value, forKeyedSubscript: key as NSString)
        }
        localContext.setObject(varsObject, forKeyedSubscript: "_currentVariables" as NSString)

        // 注入变量
        for (key, value) in variables {
            if key == "java" {
                // 为 java 对象创建包装，添加 getString 方法
                if let jsValue = value as? JSValue {
                    // 创建一个新对象，复制原对象的所有属性
                    let javaObject = localContext.objectForKeyedSubscript("Object").invokeMethod("create", withArguments: [NSNull()])!

                    // 复制所有属性
                    if let dict = jsValue.toDictionary() {
                        for (k, v) in dict {
                            if let keyStr = k as? String {
                                javaObject.setObject(v, forKeyedSubscript: keyStr as NSString)
                            }
                        }
                    }

                    // 添加 getString 方法
                    let getString: @convention(block) (String) -> String? = { key in
                        return javaObject.forProperty(key)?.toString()
                    }
                    javaObject.setObject(getString, forKeyedSubscript: "getString" as NSString)

                    localContext.setObject(javaObject, forKeyedSubscript: key as NSString)
                } else {
                    localContext.setObject(value, forKeyedSubscript: key as NSString)
                }
            } else if key == "result" {
                // 特殊处理result变量，添加toArray()方法支持（兼容Android阅读App）
                if let arrayValue = value as? [[String: Any]] {
                    // 将Swift数组转换为JSValue
                    let jsArray = JSValue(object: arrayValue, in: localContext)!

                    // 添加toArray()方法，返回自身
                    let toArrayFunc: @convention(block) () -> JSValue = {
                        return jsArray
                    }
                    jsArray.setObject(toArrayFunc, forKeyedSubscript: "toArray" as NSString)

                    localContext.setObject(jsArray, forKeyedSubscript: key as NSString)
                } else {
                    localContext.setObject(value, forKeyedSubscript: key as NSString)
                }
            } else {
                localContext.setObject(value, forKeyedSubscript: key as NSString)
            }
        }
        
        // java.getString/getStringList 是针对当前规则内容取值，不是 java.get 的别名。
        let input: String
        if let text = variables["result"] as? String { input = text }
        else if let object = variables["result"], JSONSerialization.isValidJSONObject(object),
                let data = try? JSONSerialization.data(withJSONObject: object) {
            input = String(data: data, encoding: .utf8) ?? ""
        } else { input = "" }
        let baseURL = variables["baseUrl"] as? String ?? ""
        let getString: @convention(block) (String) -> String = { rule in
            if input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || input.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                return (try? LegadoRuleParser.jsonValue(from: input, rule: rule)) ?? ""
            }
            return (try? LegadoRuleParser.value(html: input, rule: rule, baseURL: baseURL)) ?? ""
        }
        let getStrings: @convention(block) (String) -> [String] = { rule in
            (try? LegadoRuleParser.values(html: input, rule: rule, baseURL: baseURL)) ?? []
        }
        localContext.objectForKeyedSubscript("java").setObject(getString, forKeyedSubscript: "getString" as NSString)
        localContext.objectForKeyedSubscript("java").setObject(getStrings, forKeyedSubscript: "getStringList" as NSString)
        if let source = localContext.objectForKeyedSubscript("source"), !source.isUndefined {
            localContext.evaluateScript("source.getKey = function() { return this.bookSourceUrl; };")
        }

        // 执行脚本
        guard let result = localContext.evaluateScript(wrappedScript) else {
            // 清理临时变量
            localContext.setObject(JSValue(undefinedIn: localContext), forKeyedSubscript: "_currentVariables" as NSString)
            throw JavaScriptError.evaluationFailed
        }

        // 检查异常
        if let exception = localContext.exception {
            let errorMsg = exception.toString() ?? "Unknown JavaScript error"
            print("JavaScript执行详情 - 脚本: \(processedScript.prefix(100))...")
            print("JavaScript执行详情 - 错误: \(errorMsg)")
            // 清理临时变量
            localContext.setObject(JSValue(undefinedIn: localContext), forKeyedSubscript: "_currentVariables" as NSString)
            throw JavaScriptError.scriptException(errorMsg)
        }

        // 清理临时变量
        localContext.setObject(JSValue(undefinedIn: localContext), forKeyedSubscript: "_currentVariables" as NSString)

        try Task.checkCancellation()
        return result
    }
    
    /// 预处理JavaScript代码，转换ES6+语法
    private func preprocessScript(_ script: String) -> String {
        var processed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果代码以 . 开头，说明这是链式调用，已经在外部处理成 result.xxx() 的形式
        // 不应该再添加 return
        let isChainCall = processed.hasPrefix(".")
        
        // 1. 处理指数运算符 ** -> Math.pow()
        // 例如: 2**3 -> Math.pow(2,3)
        let expPattern = #"(\w+|\d+)\s*\*\*\s*(\w+|\d+)"#
        if let regex = try? NSRegularExpression(pattern: expPattern, options: []) {
            let range = NSRange(processed.startIndex..., in: processed)
            processed = regex.stringByReplacingMatches(
                in: processed,
                options: [],
                range: range,
                withTemplate: "Math.pow($1,$2)"
            )
        }
        
        // 如果是链式调用，直接返回，不添加 return
        if isChainCall {
            return processed
        }
        
        // 2. 检查最后一行并自动添加return
        let lines = processed.components(separatedBy: .newlines)
        if let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastLine.isEmpty {
            
            // 如果最后一行不是return语句
            if !lastLine.hasPrefix("return ") && !lastLine.hasPrefix("return;") {
                // 如果最后一行是表达式（不包含赋值、声明等）
                if !lastLine.contains("let ") && 
                   !lastLine.contains("var ") && 
                   !lastLine.contains("const ") &&
                   !lastLine.contains("function ") &&
                   !lastLine.hasPrefix("//") &&
                   !lastLine.hasPrefix("}") {
                    // 在最后一行前添加return
                    let otherLines = lines.dropLast().joined(separator: "\n")
                    processed = otherLines + "\nreturn \(lastLine);"
                    print("🔧 自动添加: return \(lastLine.prefix(50))...;")
                }
            }
        }
        
        return processed
    }
    
    /// 执行JavaScript规则并返回字符串结果
    func evaluateRule(_ rule: String, variables: [String: Any] = [:], jsLib: String? = nil) throws -> String {
        let result = try evaluate(rule, variables: variables, jsLib: jsLib)
        
        // 转换为字符串
        if result.isString {
            return result.toString()
        } else if result.isNumber {
            return result.toString()
        } else if result.isArray {
            // 如果是数组，返回第一个元素
            if let first = result.atIndex(0) {
                return first.toString()
            }
        }
        
        return result.toString()
    }
    
    /// 执行JavaScript规则并返回数组结果
    func evaluateRuleForArray(_ rule: String, variables: [String: Any] = [:], jsLib: String? = nil) throws -> [String] {
        let result = try evaluate(rule, variables: variables, jsLib: jsLib)
        
        if result.isArray {
            var array: [String] = []
            let length = result.forProperty("length").toInt32()
            for i in 0..<length {
                if let item = result.atIndex(Int(i)) {
                    array.append(item.toString())
                }
            }
            return array
        }
        
        // 如果不是数组，返回单个元素的数组
        return [result.toString()]
    }
    
    /// 解析并执行JS规则
    /// - Parameters:
    ///   - rule: 规则字符串（可能包含@js:、<js>等前缀）
    ///   - html: HTML内容
    ///   - baseUrl: 基础URL
    /// - Returns: 解析结果
    func parseJSRule(_ rule: String, html: String, baseUrl: String, jsLib: String? = nil) throws -> String {
        var script = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除JS标记
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4))
        } else if script.hasPrefix("<js>") && script.hasSuffix("</js>") {
            script = String(script.dropFirst(4).dropLast(5))
        } else if script.hasPrefix("{{") && script.hasSuffix("}}") {
            script = String(script.dropFirst(2).dropLast(2))
            if script.hasPrefix("@js") {
                script = String(script.dropFirst(3))
            }
        }
        
        script = script.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 准备变量
        let variables: [String: Any] = [
            "result": html,           // 当前HTML内容
            "baseUrl": baseUrl,       // 基础URL
            "html": html              // HTML别名
        ]
        
        return try evaluateRule(script, variables: variables, jsLib: jsLib)
    }
}

/// JavaScript执行错误
enum JavaScriptError: Error, LocalizedError {
    case evaluationFailed
    case scriptException(String)
    case invalidResult
    
    var errorDescription: String? {
        switch self {
        case .evaluationFailed:
            return "JavaScript执行失败"
        case .scriptException(let message):
            return "JavaScript异常: \(message)"
        case .invalidResult:
            return "JavaScript返回了无效结果"
        }
    }
}

// MARK: - String扩展：MD5

extension String {
    func md5Hash() -> String {
        let digest = Insecure.MD5.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
