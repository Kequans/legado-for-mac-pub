# 规则兼容回归用例

这些用例对应 Android Legado AnalyzeRule 的核心语义，适用于加入或更新书源后手工验证：

| 语义 | 示例规则 | 预期 |
| --- | --- | --- |
| JSOUP 链式选择 | class.book.0@tag.a@text | 取得第一本书的标题 |
| 负索引 | class.book[-1]@tag.a@href | 取得最后一本书的链接 |
| 排除索引 | tag.li[!0]@text | 排除第一个元素 |
| 区间索引 | tag.li[0:2]@text | 取得索引 0、1、2 的三个元素（JSoup 区间包含终点） |
| 连接符 | a@text||h1@text | 使用第一个非空结果 |
| 递归 JSONPath | $..books[*] | 找到嵌套任意层级的 books 数组 |
| XPath 属性 | //*[@id="content"]//a[1]/@href | 取得首个链接属性 |
| AllInOne | :href="([^"]+)">([^<]+)</a> | $1 为链接、$2 为文本 |
| OnlyOne | ##广告.*##### | 只替换首个匹配 |
| 模板变量 | {$._id}、{{$.id}} | 使用当前 JSON 对象替换 |

对照规则实现时，参考 Android 原版仓库中的：

`app/src/main/java/io/legado/app/model/analyzeRule/`

重点文件是 AnalyzeRule.kt、AnalyzeByJSoup.kt、AnalyzeByJSonPath.kt、AnalyzeByXPath.kt 和 AnalyzeByRegex.kt。
