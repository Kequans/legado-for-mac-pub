#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/legado-clang-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-/tmp/legado-swift-cache}"
swift build
bin_dir="$(swift build --show-bin-path)"
swiftc -I "$bin_dir/Modules" -I .build/checkouts/swift-atomics/Sources/_AtomicsShims/include \
  Sources/BookSource/{BookSourceEngine,LegacyRuleEvaluator,LegadoRuleParser,RuleAnalyzer,RuleConnector,JavaScriptEngine,RuleTemplate,SourceRequest,SourcePagination,JSONPathEvaluator,XPathRuleEvaluator}.swift \
  Sources/Models/{Book,BookChapter,BookSource}.swift \
  Sources/Utils/{FileUtils,Config}.swift Sources/Network/NetworkManager.swift \
  Tests/Manual/DOMRuleRegression.swift Tests/Manual/AdvancedRuleRegression.swift \
  "$bin_dir"/SwiftSoup.build/*.o "$bin_dir"/Atomics.build/*.o "$bin_dir"/LRUCache.build/*.o "$bin_dir"/_AtomicsShims.build/src/*.o \
  -o "$bin_dir/dom-rule-regression"
"$bin_dir/dom-rule-regression"
