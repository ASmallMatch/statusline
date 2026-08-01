#!/bin/bash
# Xiaomi Mimo Token Plan 用量查询 Provider
# 接口: GET https://platform.xiaomimimo.com/api/v1/tokenPlan/usage
# 认证: Cookie (api-platform_serviceToken)
# 输入: $1 = cookie 字符串(可选), $2 = api_url (可选)
# Cookie 来源: $1 > 文件 > 失败提示
# 输出: 带 ANSI 颜色的用量字符串

set -e

# 基于脚本自身位置推导安装目录（兼容自定义安装路径）
_PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_INSTALL_DIR="$(cd "$_PROVIDER_DIR/.." && pwd)"
CACHE_DIR="${_INSTALL_DIR}/cache"
COOKIE_FILE="${CACHE_DIR}/xiaomimimo_cookie.txt"
HINT_FILE="${CACHE_DIR}/xiaomimimo_hint.txt"
REFRESH_SCRIPT="${_INSTALL_DIR}/scripts/refresh-xiaomimimo-cookie.sh"
HINT_TTL=3600  # 提示信息 1 小时内不重复显示

# Cookie 来源优先级: $1 > 文件
COOKIE="$1"
if [ -z "$COOKIE" ] && [ -f "$COOKIE_FILE" ]; then
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
        printf '\033[33mMimo ⚠ 需要设置cookie\033[0m '
        printf '\033[90m(run: %s)\033[0m' "$REFRESH_SCRIPT"
    }
    show_hint
    exit 0
fi

CACHE_FILE="${CACHE_DIR}/balance_xiaomimimo.txt"
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

API_URL="${2:-https://platform.xiaomimimo.com/api/v1/tokenPlan/usage}"

RESPONSE=$(curl -s --max-time 10 "$API_URL" \
    -H "accept: */*" \
    -H "content-type: application/json" \
    -H "referer: https://platform.xiaomimimo.com/console/plan-manage" \
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
    printf '\033[33mMimo ⚠ cookie已过期\033[0m '
    printf '\033[90m(run: %s)\033[0m' "$REFRESH_SCRIPT"
}

# 尝试自动刷新 cookie
try_auto_refresh() {
    if [ -x "$REFRESH_SCRIPT" ]; then
        bash "$REFRESH_SCRIPT" --quiet 2>/dev/null || true
    fi
}

# 优先用 jq 解析
if command -v jq >/dev/null 2>&1; then
    RESP_CODE=$(echo "$RESPONSE" | jq -r '.code // 1' 2>/dev/null || echo "1")
    if [ "$RESP_CODE" != "0" ]; then
        if [ "$RESP_CODE" = "401" ]; then
            # Cookie 过期，尝试自动刷新后重试
            try_auto_refresh
            if [ -f "$COOKIE_FILE" ]; then
                NEW_COOKIE=$(cat "$COOKIE_FILE" 2>/dev/null || true)
                if [ -n "$NEW_COOKIE" ] && [ "$NEW_COOKIE" != "$COOKIE" ]; then
                    RESPONSE=$(curl -s --max-time 10 "$API_URL" \
                        -H "accept: */*" \
                        -H "content-type: application/json" \
                        -H "referer: https://platform.xiaomimimo.com/console/plan-manage" \
                        -b "$NEW_COOKIE" 2>/dev/null || true)
                    RESP_CODE=$(echo "$RESPONSE" | jq -r '.code // 1' 2>/dev/null || echo "1")
                    if [ "$RESP_CODE" = "0" ]; then
                        COOKIE="$NEW_COOKIE"
                    fi
                fi
            fi
            if [ "$RESP_CODE" != "0" ]; then
                show_cookie_expired_hint
                if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
                exit 1
            fi
        else
            if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
            exit 1
        fi
    fi

    PERCENT=$(echo "$RESPONSE" | jq -r '.data.usage.percent // .data.monthUsage.percent // empty' 2>/dev/null || true)
    PLAN_USED=$(echo "$RESPONSE" | jq -r '.data.usage.items[0].used // empty' 2>/dev/null || true)
    PLAN_LIMIT=$(echo "$RESPONSE" | jq -r '.data.usage.items[0].limit // empty' 2>/dev/null || true)
else
    # Fallback: grep/sed
    RESPONSE_FLAT=$(echo "$RESPONSE" | tr '\n' ' ')
    RESP_CODE=$(echo "$RESPONSE_FLAT" | grep -o '"code"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*$' || echo "1")
    if [ "$RESP_CODE" != "0" ]; then
        if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
        exit 1
    fi
    PERCENT=$(echo "$RESPONSE_FLAT" | grep -o '"percent"[[:space:]]*:[[:space:]]*[0-9.]*' | head -1 | grep -o '[0-9.]*$' || true)
    PLAN_USED=$(echo "$RESPONSE_FLAT" | grep -o '"plan_total_token"[[:space:]]*:[[:space:]]*{[^}]*}' | grep -o '"used"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
    PLAN_LIMIT=$(echo "$RESPONSE_FLAT" | grep -o '"plan_total_token"[[:space:]]*:[[:space:]]*{[^}]*}' | grep -o '"limit"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
fi

if [ -z "$PERCENT" ]; then
    if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; exit 0; fi
    exit 1
fi

# 转为百分比整数
PCT_INT=$(awk "BEGIN {printf \"%d\", $PERCENT * 100}")

# 颜色
if [ "$PCT_INT" -gt 90 ] 2>/dev/null; then
    COLOR="\033[31m"
elif [ "$PCT_INT" -gt 70 ] 2>/dev/null; then
    COLOR="\033[33m"
else
    COLOR="\033[32m"
fi

# 格式化 used/limit
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

if [ -n "$PLAN_USED" ] && [ -n "$PLAN_LIMIT" ] && [ "$PLAN_LIMIT" -gt 0 ] 2>/dev/null; then
    USED_FMT=$(format_tokens "$PLAN_USED")
    LIMIT_FMT=$(format_tokens "$PLAN_LIMIT")
    OUTPUT="Mimo ${COLOR}${PCT_INT}%\033[0m(${USED_FMT}/${LIMIT_FMT})"
else
    OUTPUT="Mimo ${COLOR}${PCT_INT}%\033[0m"
fi

mkdir -p "$CACHE_DIR"
printf '%b' "$OUTPUT" > "$CACHE_FILE"
printf '%b' "$OUTPUT"
