#!/usr/bin/env bash
# Swift パッケージのテストカバレッジを、モジュールごとの Markdown の表にして出力する。
# 先に `swift test --enable-code-coverage` を実行しておくこと。
#
# 使い方: scripts/swift-coverage.sh [パッケージのパス]

set -euo pipefail

package_path="${1:-Packages/SundeskKit}"
codecov_json="$(swift test --package-path "$package_path" --show-codecov-path)"

if [[ ! -f "$codecov_json" ]]; then
    echo "カバレッジのデータがありません。先に swift test --enable-code-coverage を実行してください。" >&2
    exit 1
fi

python3 - "$codecov_json" <<'PYTHON'
import json
import re
import sys
from collections import defaultdict

with open(sys.argv[1]) as f:
    data = json.load(f)

covered = defaultdict(int)
total = defaultdict(int)
for file in data["data"][0]["files"]:
    match = re.search(r"/Sources/([^/]+)/", file["filename"])
    if not match or "/.build/" in file["filename"]:
        continue  # テストや依存パッケージは数えない
    lines = file["summary"]["lines"]
    covered[match.group(1)] += lines["covered"]
    total[match.group(1)] += lines["count"]

print("| モジュール | 行カバレッジ | 行数 |")
print("|---|---:|---:|")
for module in sorted(total):
    ratio = covered[module] / total[module] * 100 if total[module] else 0
    print(f"| {module} | {ratio:.1f}% | {covered[module]} / {total[module]} |")
all_covered, all_total = sum(covered.values()), sum(total.values())
print(f"| **合計** | **{all_covered / all_total * 100:.1f}%** | {all_covered} / {all_total} |")
PYTHON
