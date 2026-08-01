#!/bin/bash
# SCNet TokenPlan 资源用量查询 Provider
# 接口: GET https://www.scnet.cn/acx/charge/account/currentuser/tokenplan/list
# 认证: Cookie (浏览器登录后获取)
# 输入: $1 = API token (仅用于 query-balance.sh 的 sk-tp 检测), $2 = api_url (可选)
# Cookie 来源: ~/.claude/statusline/cache/scnet_tp_cookie.txt
# 输出: 带 ANSI 颜色的用量字符串, 如 "\033[32mSCNet-TP 0%(0/6万CP)\033[0m"
#
# API 响应格式:
# {
#   "code": "0",
#   "data": [{
#     "name": "活动专享版",
#     "usedAmount": 0.0,
#     "totalAmount": 60000.0,
#     "unit": "CREDITS"
#   }]
# }
#
# 获取 Cookie:
#   1. 浏览器登录 https://www.scnet.cn (TokenPlan 用户)
#   2. F12 → Network → 找到任意请求 → 复制 Cookie 头
#   3. 存入 ~/.claude/statusline/cache/scnet_tp_cookie.txt

set -e

CACHE_DIR="${HOME}/.claude/statusline/cache"
COOKIE_FILE="${CACHE_DIR}/scnet_tp_cookie.txt"
HINT_FILE="${CACHE_DIR}/scnet_tp_hint.txt"
HINT_TTL=3600  # 提示信息 1 小时内不重复显示

# Cookie 仅从文件读取（$1 是 API key，不是 Cookie）
COOKIE=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE=$(cat "$COOKIE_FILE" 2>/dev/null || true)
fi

if [ -z "$COOKIE" ]; then
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
        printf '\033[33mSCNet-TP ⚠ 需要设置 Cookie\033[0m '
        printf '\033[90m(登录 scnet.cn 后复制 Cookie 到 %s)\033[0m' "$COOKIE_FILE"
    }
    show_hint
    exit 0
fi

CACHE_FILE="${CACHE_DIR}/balance_scnet_tp.txt"
CACHE_TTL=300  # 5分钟缓存

if [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    cache_age=$(($(date +%s) - cache_mtime))
    if [ "$cache_age" -lt "$CACHE_TTL" ] 2>/dev/null; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

API_URL="${2:-https://www.scnet.cn/acx/charge/account/currentuser/tokenplan/list}"

# TokenPlan 接口使用 GET
RESPONSE=$(curl -s --max-time 10 -X GET "$API_URL" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
    -H "Referer: https://www.scnet.cn/acx/charge/account/currentuser/tokenplan/list" \
    -b "$COOKIE" 2>/dev/null || true)

if [ -z "$RESPONSE" ]; then
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
    exit 1
fi

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
    printf '\033[33mSCNet-TP ⚠ Cookie已过期\033[0m '
    printf '\033[90m(请重新登录 scnet.cn 并更新 Cookie)\033[0m'
}

if command -v jq >/dev/null 2>&1; then
    RESP_CODE=$(echo "$RESPONSE" | jq -r '.code // "1"' 2>/dev/null || echo "1")
    if [ "$RESP_CODE" != "0" ]; then
        show_cookie_expired_hint
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi

    # 聚合所有 TokenPlan 资源
    TOTAL_AMOUNT=$(echo "$RESPONSE" | jq '[.data[] | .totalAmount | tonumber] | add // 0' 2>/dev/null || echo "0")
    USED_AMOUNT=$(echo "$RESPONSE" | jq '[.data[] | .usedAmount | tonumber] | add // 0' 2>/dev/null || echo "0")
    UNIT=$(echo "$RESPONSE" | jq -r '.data[0].unit // ""' 2>/dev/null || echo "")
else
    RESPONSE_FLAT=$(echo "$RESPONSE" | tr '\n' ' ')
    RESP_CODE=$(echo "$RESPONSE_FLAT" | grep -o '"code"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || echo "1")
    if [ "$RESP_CODE" != "0" ]; then
        show_cookie_expired_hint
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi
    TOTAL_AMOUNT=$(echo "$RESPONSE_FLAT" | grep -o '"totalAmount"[[:space:]]*:[[:space:]]*[0-9.]*' | head -1 | grep -o '[0-9.]*$' || echo "0")
    USED_AMOUNT=$(echo "$RESPONSE_FLAT" | grep -o '"usedAmount"[[:space:]]*:[[:space:]]*[0-9.eE\-]*' | head -1 | grep -o '[0-9.eE\-]*$' || echo "0")
    UNIT=$(echo "$RESPONSE_FLAT" | grep -o '"unit"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || echo "")
fi

if [ -z "$TOTAL_AMOUNT" ] || [ "$(echo "$TOTAL_AMOUNT == 0" | bc 2>/dev/null || echo 1)" = "1" ]; then
    if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
    exit 1
fi

# 计算使用量（bc 处理浮点数）
USED=$(echo "$USED_AMOUNT" | sed 's/[eE].*$//' 2>/dev/null || echo "0")
PCT=$(awk "BEGIN {printf \"%d\", $USED_AMOUNT * 100 / $TOTAL_AMOUNT}" 2>/dev/null || echo "0")

# 颜色
if [ "$PCT" -gt 90 ] 2>/dev/null; then
    COLOR="\033[31m"
elif [ "$PCT" -gt 70 ] 2>/dev/null; then
    COLOR="\033[33m"
else
    COLOR="\033[32m"
fi

# 已用量取整
USED_INT=$(awk "BEGIN {printf \"%.0f\", $USED_AMOUNT}" 2>/dev/null || echo "0")
TOTAL_INT=$(awk "BEGIN {printf \"%.0f\", $TOTAL_AMOUNT}" 2>/dev/null || echo "0")

# 格式化显示
format_tp_amount() {
    local val="$1"
    local int_val=$(awk "BEGIN {printf \"%.0f\", $val}" 2>/dev/null || echo "0")
    if [ "$int_val" = "0" ]; then
        echo "0"
    elif [ "$int_val" -ge 100000000 ] 2>/dev/null; then
        awk "BEGIN {printf \"%.1f亿\", $val/100000000}"
    elif [ "$int_val" -ge 10000 ] 2>/dev/null; then
        awk "BEGIN {printf \"%d万\", $val/10000}"
    else
        echo "$int_val"
    fi
}

TOTAL_FMT=$(format_tp_amount "$TOTAL_AMOUNT")
USED_FMT=$(format_tp_amount "$USED_AMOUNT")

OUTPUT="SCNet-TP ${COLOR}${PCT}%\033[0m(${USED_FMT}/${TOTAL_FMT})"

mkdir -p "$CACHE_DIR"
printf '%b' "$OUTPUT" > "$CACHE_FILE"
printf '%b' "$OUTPUT"