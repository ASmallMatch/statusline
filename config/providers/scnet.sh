#!/bin/bash
# SCNet 资源用量查询 Provider (API 模式)
# 接口: POST https://www.scnet.cn/acx/charge/flow/llmapi/resource/list
# 认证: Cookie (浏览器登录后获取)
# 输入: $1 = API token (仅用于 query-balance.sh 的 sk-tp 检测), $2 = api_url (可选)
# Cookie 来源: ~/.claude/statusline/cache/scnet_cookie.txt
# 输出: 带 ANSI 颜色的用量字符串, 如 "\033[32mSCNet 49%\033[0m(490万/1000万)"
#
# 获取 Cookie:
#   1. 浏览器登录 https://www.scnet.cn
#   2. F12 → Network → 找到任意请求 → 复制 Cookie 头
#   3. 存入 ~/.claude/statusline/cache/scnet_cookie.txt

set -e

CACHE_DIR="${HOME}/.claude/statusline/cache"
COOKIE_FILE="${CACHE_DIR}/scnet_cookie.txt"
HINT_FILE="${CACHE_DIR}/scnet_hint.txt"
HINT_TTL=3600  # 提示信息 1 小时内不重复显示

# Cookie 仅从文件读取（$1 是 API key，不是 Cookie）
COOKIE=""
if [ -f "$COOKIE_FILE" ]; then
    COOKIE=$(cat "$COOKIE_FILE" 2>/dev/null || true)
fi

if [ -z "$COOKIE" ]; then
    # Cookie 不存在，显示提示（限频）
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
        printf '\033[33mSCNet ⚠ 需要设置 Cookie\033[0m '
        printf '\033[90m(登录 scnet.cn 后复制 Cookie 到 %s)\033[0m' "$COOKIE_FILE"
    }
    show_hint
    exit 0
fi

CACHE_FILE="${CACHE_DIR}/balance_scnet.txt"
CACHE_TTL=300  # 5分钟缓存

# 读取缓存
if [ -f "$CACHE_FILE" ]; then
    cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    cache_age=$(($(date +%s) - cache_mtime))
    if [ "$cache_age" -lt "$CACHE_TTL" ] 2>/dev/null; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

API_URL="${2:-https://www.scnet.cn/acx/charge/flow/llmapi/resource/list}"

RESPONSE=$(curl -s --max-time 10 -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
    -H "Referer: https://www.scnet.cn/flow/llmapi/resource/list" \
    -b "$COOKIE" 2>/dev/null || true)

if [ -z "$RESPONSE" ]; then
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
    exit 1
fi

# Cookie 过期提示
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
    printf '\033[33mSCNet ⚠ Cookie已过期\033[0m '
    printf '\033[90m(请重新登录 scnet.cn 并更新 Cookie)\033[0m'
}

# 解析响应
if command -v jq >/dev/null 2>&1; then
    RESP_CODE=$(echo "$RESPONSE" | jq -r '.code // "1"' 2>/dev/null || echo "1")
    if [ "$RESP_CODE" != "0" ]; then
        show_cookie_expired_hint
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi

    # 聚合所有 LLMAPI 类型资源
    TOTAL_PURCHASE=$(echo "$RESPONSE" | jq '[.data[] | select(.unit == "TOKENS") | .purchaseCount | tonumber] | add // 0' 2>/dev/null || echo "0")
    TOTAL_BALANCE=$(echo "$RESPONSE" | jq '[.data[] | select(.unit == "TOKENS") | .balance | tonumber] | add // 0' 2>/dev/null || echo "0")
else
    # Fallback: grep/sed
    RESPONSE_FLAT=$(echo "$RESPONSE" | tr '\n' ' ')
    RESP_CODE=$(echo "$RESPONSE_FLAT" | grep -o '"code"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || echo "1")
    if [ "$RESP_CODE" != "0" ]; then
        show_cookie_expired_hint
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi

    # 提取所有 purchaseCount 和 balance 并求和（简单实现，取第一个）
    TOTAL_PURCHASE=$(echo "$RESPONSE_FLAT" | grep -o '"purchaseCount"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || echo "0")
    TOTAL_BALANCE=$(echo "$RESPONSE_FLAT" | grep -o '"balance"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || echo "0")
fi

if [ -z "$TOTAL_PURCHASE" ] || [ "$TOTAL_PURCHASE" = "0" ] || [ -z "$TOTAL_BALANCE" ]; then
    if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
    exit 1
fi

# 计算使用量
USED=$((TOTAL_PURCHASE - TOTAL_BALANCE))
PCT=$((USED * 100 / TOTAL_PURCHASE))

# 颜色（使用率越高越红）
if [ "$PCT" -gt 90 ] 2>/dev/null; then
    COLOR="\033[31m"  # 红色
elif [ "$PCT" -gt 70 ] 2>/dev/null; then
    COLOR="\033[33m"  # 黄色
else
    COLOR="\033[32m"  # 绿色
fi

# 格式化大数字（万/亿）
format_tokens() {
    local val="$1"
    if [ "$val" -ge 100000000 ] 2>/dev/null; then
        awk "BEGIN {printf \"%.1f亿\", $val/100000000}"
    elif [ "$val" -ge 10000 ] 2>/dev/null; then
        awk "BEGIN {printf \"%d万\", $val/10000}"
    else
        echo "$val"
    fi
}

USED_FMT=$(format_tokens "$USED")
LIMIT_FMT=$(format_tokens "$TOTAL_PURCHASE")

OUTPUT="SCNet ${COLOR}${PCT}%\033[0m(${USED_FMT}/${LIMIT_FMT})"

mkdir -p "$CACHE_DIR"
printf '%b' "$OUTPUT" > "$CACHE_FILE"
printf '%b' "$OUTPUT"