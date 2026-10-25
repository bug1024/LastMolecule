#!/bin/sh
# 跑全部测试。除了失败的检查，任何脚本运行时错误（会让某个测试函数中途退出、跳过后续检查）也算失败。
# 用法：tests/run.sh [-- --sim=N ...]（GODOT 环境变量可指定 Godot 可执行文件）
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 2
LOG="$(mktemp)"
"$GODOT" --headless --path . --script tests/run_tests.gd "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "checks, [0-9]+ failures" "$LOG"
if grep -q "SCRIPT ERROR" "$LOG"; then
	echo "FAILED: script errors during tests:"
	grep -A4 "SCRIPT ERROR" "$LOG"
	STATUS=1
fi
if [ "$STATUS" -ne 0 ]; then
	grep -A3 "^ERROR:" "$LOG" | grep -v "resources still in use" | head -40
fi
rm -f "$LOG"
exit "$STATUS"
