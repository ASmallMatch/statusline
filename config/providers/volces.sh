#!/bin/bash
# 火山方舟 (Volcengine Ark) 套餐用量查询 Provider
# 支持 Coding Plan 与 Agent Plan,根据 ANTHROPIC_BASE_URL 的 path 自动路由:
#   /api/coding → GetCodingPlanUsage (标签 方舟Coding)
#   /api/plan   → GetAgentPlanAFPUsage (标签 方舟Agent)
# 认证: Cookie + x-csrf-token (浏览器登录 console.volcengine.com 后获取)
# 输入: $1 = API token (仅用于 query-balance.sh 的 token 非空检查,不参与请求)
#       $2 = api_url (可选,仅作基础前缀标识)
# Cookie 来源: ~/.claude/statusline/cache/volces_cookie.txt
# 输出: 带 ANSI 颜色的用量字符串, 如 "\033[33m方舟Coding 21%\033[0m/\033[32m3%\033[0m"
#
# 接口返回格式:
#   Coding Plan  Result.QuotaUsage[] = [{Level:session|weekly|monthly, Percent, ResetTimestamp}]
#   Agent Plan   Result.AFPFiveHour{Quota,Used} / Result.AFPWeekly{Quota,Used} / ...
#
# 获取 Cookie:
#   1. 浏览器登录 https://console.volcengine.com
#   2. F12 → Network → 找到任意请求 → 复制 Cookie 头(需含 userInfo / digest / csrfToken)
#   3. 存入 ~/.claude/statusline/cache/volces_cookie.txt
# 注意: Cookie 中 digest JWT 约 2 天过期,过期后需重新复制。

set -e

CACHE_DIR="${HOME}/.claude/statusline/cache"
COOKIE_FILE="${CACHE_DIR}/volces_cookie.txt"
HINT_FILE="${CACHE_DIR}/volces_hint.txt"
HINT_TTL=3600  # 提示信息 1 小时内不重复显示

# Cookie 仅从文件读取($1 是 API key,不是 Cookie)
COOKIE=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE=$(cat "$COOKIE_FILE" 2>/dev/null || true)
fi

# 限频提示: Cookie 缺失
show_hint() {
    local now
    now=$(date +%s)
    if [ -f "$HINT_FILE" ]; then
        local last
        last=$(cat "$HINT_FILE" 2>/dev/null || echo 0)
        if [ $((now - last)) -lt "$HINT_TTL" ] 2>/dev/null; then
            return
        fi
    fi
    echo "$now" > "$HINT_FILE"
    printf '\033[33m方舟 ⚠ 需要设置 Cookie\033[0m '
    printf '\033[90m(登录 console.volcengine.com 后复制 Cookie 到 %s)\033[0m' "$COOKIE_FILE"
}

# 限频提示: Cookie 过期
show_cookie_expired_hint() {
    local now
    now=$(date +%s)
    if [ -f "$HINT_FILE" ]; then
        local last
        last=$(cat "$HINT_FILE" 2>/dev/null || echo 0)
        if [ $((now - last)) -lt "$HINT_TTL" ] 2>/dev/null; then
            return
        fi
    fi
    echo "$now" > "$HINT_FILE"
    printf '\033[33m方舟 ⚠ Cookie已过期\033[0m '
    printf '\033[90m(请重新登录 console.volcengine.com 并更新 Cookie)\033[0m'
}

# 根据 ANTHROPIC_BASE_URL 的 path 区分 Coding / Agent Plan
BASE_URL="${ANTHROPIC_BASE_URL:-}"
API_BASE="https://console.volcengine.com/api/top/ark/cn-beijing/2024-01-01"

if [[ "$BASE_URL" == */api/plan* ]]; then
    ACTION="GetAgentPlanAFPUsage"
    PLAN_PATH="agent-plan"
    LABEL="方舟Agent"
    CACHE_FILE="${CACHE_DIR}/balance_volces_agent.txt"
else
    # 默认 Coding Plan (含 /api/coding 或无法判断时)
    ACTION="GetCodingPlanUsage"
    PLAN_PATH="coding-plan"
    LABEL="方舟Coding"
    CACHE_FILE="${CACHE_DIR}/balance_volces_coding.txt"
fi

CACHE_TTL=300  # 5分钟缓存

if [ -z "$COOKIE" ]; then
    show_hint
    exit 0
fi

# 从 Cookie 中提取 csrfToken 值作为 x-csrf-token 头
CSRF_TOKEN=$(echo "$COOKIE" | grep -o 'csrfToken=[^;]*' | head -1 | sed 's/csrfToken=//' || true)

# 读取缓存
if [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    cache_age=$(($(date +%s) - cache_mtime))
    if [ "$cache_age" -lt "$CACHE_TTL" ] 2>/dev/null; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

REFERER="https://console.volcengine.com/ark/region:cn-beijing/subscription/${PLAN_PATH}"

RESPONSE=$(curl -s --max-time 10 -X POST "${API_BASE}/${ACTION}?" \
    -H "Content-Type: application/json" \
    -H "accept: application/json, text/plain, */*" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
    -H "Referer: ${REFERER}" \
    -H "Origin: https://console.volcengine.com" \
    -H "x-csrf-token: ${CSRF_TOKEN}" \
    -b "$COOKIE" \
    --data-raw '{}' 2>/dev/null || true)

if [ -z "$RESPONSE" ]; then
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
    exit 1
fi

# 颜色函数: 按使用率着色 (>90 红 / >70 黄 / 否则绿)
color_for_pct() {
    local pct="$1"
    if [ "$pct" -gt 90 ] 2>/dev/null; then
        printf '\033[31m'
    elif [ "$pct" -gt 70 ] 2>/dev/null; then
        printf '\033[33m'
    else
        printf '\033[32m'
    fi
}

PCT_5H=""
PCT_WEEK=""

if command -v jq >/dev/null 2>&1; then
    # 检查是否登录失败
    ERR_CODE=$(echo "$RESPONSE" | jq -r '.ResponseMetadata.Error.Code // empty' 2>/dev/null || true)
    if [ -n "$ERR_CODE" ]; then
        show_cookie_expired_hint
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi

    if [ "$ACTION" = "GetCodingPlanUsage" ]; then
        # QuotaUsage[] 按 Level 取 session / weekly 的 Percent
        PCT_5H=$(echo "$RESPONSE" | jq -r '[.Result.QuotaUsage[] | select(.Level == "session") | .Percent][0] // empty' 2>/dev/null || true)
        PCT_WEEK=$(echo "$RESPONSE" | jq -r '[.Result.QuotaUsage[] | select(.Level == "weekly") | .Percent][0] // empty' 2>/dev/null || true)
    else
        # AFPFiveHour / AFPWeekly 的 Used/Quota*100
        PCT_5H=$(echo "$RESPONSE" | jq -r 'if .Result.AFPFiveHour.Quota > 0 then (.Result.AFPFiveHour.Used * 100 / .Result.AFPFiveHour.Quota) else 0 end' 2>/dev/null || true)
        PCT_WEEK=$(echo "$RESPONSE" | jq -r 'if .Result.AFPWeekly.Quota > 0 then (.Result.AFPWeekly.Used * 100 / .Result.AFPWeekly.Quota) else 0 end' 2>/dev/null || true)
    fi
else
    # Fallback: grep/sed
    RESPONSE_FLAT=$(echo "$RESPONSE" | tr '\n' ' ')
    if echo "$RESPONSE_FLAT" | grep -q '"NotLogin"\|"Code":"NotLogin"'; then
        show_cookie_expired_hint
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi

    if [ "$ACTION" = "GetCodingPlanUsage" ]; then
        # 提取 session 和 weekly 段内的 Percent
        PCT_5H=$(echo "$RESPONSE_FLAT" | grep -o '"Level":"session","Percent":[0-9.]*' | grep -o '[0-9.]*$' | head -1 || true)
        PCT_WEEK=$(echo "$RESPONSE_FLAT" | grep -o '"Level":"weekly","Percent":[0-9.]*' | grep -o '[0-9.]*$' | head -1 || true)
    else
        # AFPFiveHour / AFPWeekly 的 Quota 与 Used (字段顺序可能不定,简单提取第一个匹配)
        FIVE_QUOTA=$(echo "$RESPONSE_FLAT" | sed 's/"AFPFiveHour"/\n&/g' | grep '"AFPFiveHour"' | head -1 | grep -o '"Quota":[0-9]*' | grep -o '[0-9]*$' | head -1 || echo 0)
        FIVE_USED=$(echo "$RESPONSE_FLAT" | sed 's/"AFPFiveHour"/\n&/g' | grep '"AFPFiveHour"' | head -1 | grep -o '"Used":[0-9]*' | grep -o '[0-9]*$' | head -1 || echo 0)
        WEEK_QUOTA=$(echo "$RESPONSE_FLAT" | sed 's/"AFPWeekly"/\n&/g' | grep '"AFPWeekly"' | head -1 | grep -o '"Quota":[0-9]*' | grep -o '[0-9]*$' | head -1 || echo 0)
        WEEK_USED=$(echo "$RESPONSE_FLAT" | sed 's/"AFPWeekly"/\n&/g' | grep '"AFPWeekly"' | head -1 | grep -o '"Used":[0-9]*' | grep -o '[0-9]*$' | head -1 || echo 0)
        [ -n "$FIVE_QUOTA" ] && [ "$FIVE_QUOTA" -gt 0 ] 2>/dev/null && PCT_5H=$(awk "BEGIN {printf \"%d\", $FIVE_USED * 100 / $FIVE_QUOTA}") || PCT_5H="0"
        [ -n "$WEEK_QUOTA" ] && [ "$WEEK_QUOTA" -gt 0 ] 2>/dev/null && PCT_WEEK=$(awk "BEGIN {printf \"%d\", $WEEK_USED * 100 / $WEEK_QUOTA}") || PCT_WEEK="0"
    fi
fi

if [ -z "$PCT_5H" ] && [ -z "$PCT_WEEK" ]; then
    if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
    exit 1
fi

# 取整 (Coding Plan 返回浮点, Agent Plan 已是计算值)
PCT_5H_INT=$(awk "BEGIN {printf \"%d\", ${PCT_5H:-0}}" 2>/dev/null || echo "0")
PCT_WEEK_INT=$(awk "BEGIN {printf \"%d\", ${PCT_WEEK:-0}}" 2>/dev/null || echo "0")

# 各自独立着色
COLOR_5H=$(color_for_pct "$PCT_5H_INT")
COLOR_WEEK=$(color_for_pct "$PCT_WEEK_INT")

OUTPUT="${LABEL} ${COLOR_5H}${PCT_5H_INT}%\033[0m/${COLOR_WEEK}${PCT_WEEK_INT}%\033[0m"

mkdir -p "$CACHE_DIR"
printf '%b' "$OUTPUT" > "$CACHE_FILE"
printf '%b' "$OUTPUT"
