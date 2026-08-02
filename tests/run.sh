#!/bin/bash
# 端到端测试：statusline.sh CLI（stdin JSON -> stdout 状态栏文本）
# 单一端到端接缝，纯 bash assert，零依赖。
# 用法：bash tests/run.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$PROJECT_ROOT/bin/statusline.sh"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
assert_contains() { # desc haystack needle
    if printf '%s' "$2" | grep -q -- "$3"; then
        pass "$1"
    else
        fail "$1 (缺: $3)"
    fi
}
assert_not_contains() { # desc haystack needle
    if printf '%s' "$2" | grep -q -- "$3"; then
        fail "$1 (不应含: $3)"
    else
        pass "$1"
    fi
}

# 当前 epoch 秒（优先 bash 内建，避免 fork；不支持则 fallback date）
now_epoch() {
    printf '%(%s)T' -1 2>/dev/null || date +%s
}

# 计时跑一次 statusline，stdout 存入 _OUT，耗时(ms)存入 _ELAPSED
run_timed() { # input
    local input="$1"
    local ts te
    ts=$EPOCHREALTIME
    _OUT=$(printf '%s' "$input" | bash "$STATUSLINE" 2>/dev/null)
    te=$EPOCHREALTIME
    _ELAPSED=$(awk -v s="$ts" -v e="$te" 'BEGIN{printf "%.0f", (e - s) * 1000}')
}

# ---------- 临时环境 ----------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_STATUSLINE_DIR="$WORK"
mkdir -p "$WORK/cache"
cp "$PROJECT_ROOT/config/config.json" "$WORK/config.json"

# 预置余额统一缓存（独特标记，供缓存命中断言用）
printf '\033[33mTEST_BALANCE_MARKER\033[0m' > "$WORK/cache/balance_current.txt"
# 预置节流标记为"刚刚刷新"，让优化后的后台刷新被节流跳过（测试不依赖网络/后台 spawn）
now_epoch > "$WORK/cache/balance_refresh.marker"
# 预置 config 解析缓存（模拟常态命中，避免测试每次走 node miss 路径）
cat > "$WORK/cache/config_parsed.sh" <<'CFGEOF'
green_threshold="55"
yellow_threshold="75"
bar_length="10"
show_git="true"
show_time="true"
branch_color="33"
show_tools="true"
show_agents="true"
show_todos="true"
show_git_changes="true"
CFGEOF

INPUT="{\"cwd\":\"$PROJECT_ROOT\",\"display_name\":\"Claude Sonnet 4.6\",\"used_percentage\":30}"

# ---------- Test 1: 功能断言 ----------
echo "== Test 1: 功能断言 =="
run_timed "$INPUT"
assert_contains "含路径 statusline" "$_OUT" "statusline"
assert_contains "含进度条符号" "$_OUT" "❦"
assert_contains "含 git 分支 master" "$_OUT" "master"
assert_contains "含时间 HH:MM" "$_OUT" "[0-9][0-9]:[0-9][0-9]"

# ---------- Test 2: 余额缓存命中 + 节流不 spawn（stale-while-revalidate）----------
echo "== Test 2: 余额缓存命中 + 节流 =="
_marker_before=$(cat "$WORK/cache/balance_refresh.marker" 2>/dev/null)
run_timed "$INPUT"
assert_contains "余额读预置缓存标记" "$_OUT" "TEST_BALANCE_MARKER"
_marker_after=$(cat "$WORK/cache/balance_refresh.marker" 2>/dev/null)
if [ "$_marker_before" = "$_marker_after" ]; then
    pass "节流标记未变（未重复 spawn 调度器）"
else
    fail "节流标记变化（意外 spawn 了调度器）"
fi

# ---------- Test 3: 性能断言（同步路径 < 300ms，3 次取中位数）----------
echo "== Test 3: 性能断言 (<300ms, 中位数) =="
_t=()
for i in 1 2 3; do
    run_timed "$INPUT"
    _t+=("$_ELAPSED")
done
_median=$(printf '%s\n' "${_t[@]}" | sort -n | sed -n '2p')
echo "  3 次耗时: ${_t[*]} ms, 中位数: $_median ms"
if [ "$_median" -lt 300 ] 2>/dev/null; then
    pass "中位数 < 300ms"
else
    fail "中位数 < 300ms (实际 $_median ms)"
fi

# ---------- Test 4: git 变动统计（合并调用后行为等价）----------
echo "== Test 4: git 变动统计 =="
REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email t@t 2>/dev/null
git -C "$REPO" config user.name t 2>/dev/null
printf 'a\n' > "$REPO/committed.txt"
git -C "$REPO" add . 2>/dev/null
git -C "$REPO" commit -qm init 2>/dev/null
printf 'aa\n' > "$REPO/committed.txt"
printf 'b\n' > "$REPO/new.txt"
run_timed "{\"cwd\":\"$REPO\",\"display_name\":\"Claude\",\"used_percentage\":10}"
assert_contains "git 变动含 modified(~1)" "$_OUT" "~1"
assert_contains "git 变动含 added(+1)" "$_OUT" "+1"

# ---------- Test 5: 降级（无余额缓存仍输出主行且 < 300ms）----------
echo "== Test 5: 降级（无余额缓存）=="
rm -f "$WORK/cache/balance_current.txt"
run_timed "$INPUT"
assert_contains "降级仍含路径" "$_OUT" "statusline"
assert_contains "降级仍含进度条" "$_OUT" "❦"
assert_not_contains "降级不含余额标记" "$_OUT" "TEST_BALANCE_MARKER"
if [ "$_ELAPSED" -lt 300 ] 2>/dev/null; then
    pass "降级耗时 < 300ms ($_ELAPSED ms)"
else
    fail "降级耗时 < 300ms (实际 $_ELAPSED ms)"
fi

# ---------- Test 6: transcript 统计缓存命中（同步路径零 fork 读缓存）----------
echo "== Test 6: transcript 统计缓存命中 =="
TRANSCRIPT="$WORK/transcript.jsonl"
printf '{"message":{"content":[]}}\n' > "$TRANSCRIPT"
TSTATS="$WORK/cache/transcript_stats_${TRANSCRIPT//[^a-zA-Z0-9._-]/_}.txt"
cat > "$TSTATS" <<'TSEOF'
tools_running=2
agents_running=1
todos_in_progress=1
todos_total=3
TSEOF
touch "$TSTATS"
run_timed "{\"cwd\":\"$PROJECT_ROOT\",\"display_name\":\"Claude\",\"used_percentage\":10,\"transcript_path\":\"$TRANSCRIPT\"}"
assert_contains "活动行 Tools 2 running" "$_OUT" "Tools  2 running"
assert_contains "活动行 Agents 1 running" "$_OUT" "Agents 1 running"
assert_contains "活动行 Todos 1/3" "$_OUT" "Todos  1/3"
# 缓存命中不应 spawn 后台 parser（统计文件不被改写）
sleep 1
if grep -q "tools_running=2" "$TSTATS" 2>/dev/null; then
    pass "缓存命中未触发后台刷新"
else
    fail "缓存命中却触发了后台刷新（统计被改写）"
fi
echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
