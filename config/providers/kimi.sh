#!/bin/bash
# Kimi Coding Plan 用量查询 Provider
# 接口: GET https://api.kimi.com/coding/v1/usages
# 输入: $1 = token, $2 = api_url (可选)
# 输出: 带 ANSI 颜色的用量字符串, 如 "\033[32mKimi 214/2048\033[0m"

set -e

TOKEN="$1"
if [ -z "$TOKEN" ]; then
    exit 1
fi

CACHE_DIR="${HOME}/.claude/statusline/cache"
CACHE_FILE="${CACHE_DIR}/balance_kimi.txt"
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

API_URL="${2:-https://api.kimi.com/coding/v1/usages}"

RESPONSE=$(curl -s --max-time 5 "$API_URL" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" 2>/dev/null || true)

if [ -z "$RESPONSE" ]; then
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
    exit 1
fi

# 把 JSON 压成一行，方便提取嵌套字段
RESPONSE_FLAT=$(echo "$RESPONSE" | tr '\n' ' ')

# 提取周度配额 (usage.detail)
USAGE_SECTION=$(echo "$RESPONSE_FLAT" | grep -o '"usage"[[:space:]]*:[[:space:]]*{[^}]*}' || true)
WEEKLY_LIMIT=$(echo "$USAGE_SECTION" | grep -o '"limit"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)
WEEKLY_USED=$(echo "$USAGE_SECTION" | grep -o '"used"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

# 如果没有 used，尝试 remaining
if [ -z "$WEEKLY_USED" ] && [ -n "$WEEKLY_LIMIT" ]; then
    WEEKLY_REMAINING=$(echo "$USAGE_SECTION" | grep -o '"remaining"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)
    if [ -n "$WEEKLY_REMAINING" ]; then
        WEEKLY_USED=$((WEEKLY_LIMIT - WEEKLY_REMAINING))
    fi
fi

# 提取 5 小时速率限制 (limits[0].detail)
LIMITS_SECTION=$(echo "$RESPONSE_FLAT" | grep -o '"limits"[[:space:]]*:[[:space:]]*\[[^]]*\]' || true)
RL_DETAIL=$(echo "$LIMITS_SECTION" | grep -o '"detail"[[:space:]]*:[[:space:]]*{[^}]*}' | head -1 || true)
RL_LIMIT=$(echo "$RL_DETAIL" | grep -o '"limit"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)
RL_USED=$(echo "$RL_DETAIL" | grep -o '"used"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

# 如果没有 used，尝试 remaining
if [ -z "$RL_USED" ] && [ -n "$RL_LIMIT" ]; then
    RL_REMAINING=$(echo "$RL_DETAIL" | grep -o '"remaining"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)
    if [ -n "$RL_REMAINING" ]; then
        RL_USED=$((RL_LIMIT - RL_REMAINING))
    fi
fi

# 验证数据完整性
if [ -z "$WEEKLY_USED" ] || [ -z "$WEEKLY_LIMIT" ] || [ "$WEEKLY_LIMIT" -eq 0 ] 2>/dev/null; then
    if [ -f "$CACHE_FILE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
    exit 1
fi

# 计算百分比（5小时在前，周度在后）
RL_PCT=$((RL_USED * 100 / RL_LIMIT))
WEEKLY_PCT=$((WEEKLY_USED * 100 / WEEKLY_LIMIT))

# 5小时窗口颜色（速率限制，阈值更严格）
if [ "$RL_PCT" -gt 80 ] 2>/dev/null; then
    RL_COLOR="\033[31m"  # 红色
elif [ "$RL_PCT" -gt 50 ] 2>/dev/null; then
    RL_COLOR="\033[33m"  # 黄色
else
    RL_COLOR="\033[32m"  # 绿色
fi

# 周度配额颜色（总量限制，阈值更宽松）
if [ "$WEEKLY_PCT" -gt 90 ] 2>/dev/null; then
    WK_COLOR="\033[31m"  # 红色
elif [ "$WEEKLY_PCT" -gt 70 ] 2>/dev/null; then
    WK_COLOR="\033[33m"  # 黄色
else
    WK_COLOR="\033[32m"  # 绿色
fi

OUTPUT="Kimi ${RL_COLOR}${RL_PCT}%\033[0m/${WK_COLOR}${WEEKLY_PCT}%\033[0m"

mkdir -p "$CACHE_DIR"
printf '%b' "$OUTPUT" > "$CACHE_FILE"
printf '%b' "$OUTPUT"
