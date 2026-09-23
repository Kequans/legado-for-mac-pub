# 手工测试

这些脚本验证数据库初始化、RSS 数据模型、JSON 结构和基础解析逻辑。

它们依赖项目源码或 macOS Swift 环境，当前不属于 SwiftPM 自动测试 target。运行前先完成一次：

```bash
swift build
```

脚本说明：

- test_integration.swift：RSS 数据库 CRUD 集成检查。
- test_rss.swift：RSS 模型和规则基础检查。
- test_rss_engine.swift：RSS/Atom 文本解析基础检查。
- test_rss_source_json.swift：订阅源 JSON 结构检查。
- LocalBookImportPerformance.md：本地 TXT/EPUB 按章节读取、阅读页局部导航、缓存清理和备份恢复检查。
- BookSourceSearchAndImport.md：书源搜索取消、书籍信息回填和 `@put/@get` 规则回归检查。

历史脚本中的绝对路径和旧日志仅用于追溯，新增测试应使用仓库相对路径。

运行 `bash Tests/Manual/run_dom_regression.sh` 验证 Android DOM 规则兼容性（11 项离线断言，不依赖 XCTest）。

`AdvancedRuleRegression.swift` 随 `run_dom_regression.sh` 运行，覆盖模板、查询语法、JS 隔离和内存网络请求/分页/取消。无需访问公网。
