#!/bin/bash
# 余额查询调度器
# balance 为对象格式，key 是 provider 名
# 通过 ANTHROPIC_BASE_URL 推断当前使用的 provider，直接从 balance[key] 获取配置
# Provider 约定: $1 = API token, $2 = api_url (可选), 输出带 ANSI 颜色的字符串, 退出码 0=成功

set -e

# 加载布局模块（dev: bin/../lib/layout.sh；安装: 同目录 layout.sh）
if [ -f "${BASH_SOURCE[0]%/*}/../lib/layout.sh" ]; then
    source "${BASH_SOURCE[0]%/*}/../lib/layout.sh"
else
    source "${BASH_SOURCE[0]%/*}/layout.sh"
fi
load_module "json.sh"  # settings.json 的 grep 兜底

SETTINGS_FILE="$HOME/.claude/settings.json"

# 确定配置文件路径：优先项目配置（开发模式），其次安装目录配置
# （lib/layout.sh 统一双布局定位：dev 命中 config/，安装命中布局根）
CONFIG_FILE=$(find_file "config.json" 2>/dev/null || true)

# 检查配置文件是否存在
[ -f "$CONFIG_FILE" ] || exit 0

# 查找 provider 脚本目录（lib/layout.sh 统一双布局定位）
PROVIDER_DIR=$(find_dir "providers" 2>/dev/null || true)

[ -n "$PROVIDER_DIR" ] || exit 0

# 从 settings.json 或环境变量读取值
# 支持逗号分隔的多值（如 "ANTHROPIC_AUTH_TOKEN,DEEPSEEK_API_KEY"），使用第一个非空值
resolve_value() {
    local var_names="$1"
    local value=""

    local saved_ifs="$IFS"
    IFS=','
    for var_name in $var_names; do
        IFS="$saved_ifs"
        [ -z "$var_name" ] && continue
        # 去除首尾空格
        var_name="${var_name#"${var_name%%[![:space:]]*}"}"
        var_name="${var_name%"${var_name##*[![:space:]]}"}"
        [ -z "$var_name" ] && continue

        # 1. 环境变量
        eval value="\$$var_name" 2>/dev/null || true
        [ -n "$value" ] && break

        # 2. settings.json (via node, 兼容 env 子对象)
        if [ -f "$SETTINGS_FILE" ] && command -v node >/dev/null 2>&1; then
            value=$(node -e "
                const fs = require('fs');
                const s = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
                const keys = process.argv[2].split('.');
                for (const root of [s, s.env]) {
                    if (!root) continue;
                    let v = root;
                    for (const k of keys) { v = v?.[k]; }
                    if (v != null) { process.stdout.write(String(v)); break; }
                }
            " "$SETTINGS_FILE" "$var_name" 2>/dev/null || true)
        fi
        [ -n "$value" ] && break

        # 3. json_get 兜底（lib/json.sh 的 awk 实现，支持嵌套路径）
        if [ -f "$SETTINGS_FILE" ]; then
            value=$(json_get "$SETTINGS_FILE" "$var_name" "")
        fi
        [ -n "$value" ] && break
    done
    IFS="$saved_ifs"
    echo "$value"
}

# 从 URL 中提取 provider 标识
# https://api.kimi.com/coding/     → kimi
# https://api.deepseek.com/v1/     → deepseek
# https://api.moonshot.cn/v1/      → moonshot
# https://api.openai.com/v1/       → openai
# https://api.anthropic.com/v1/    → anthropic
# https://api.groq.com/openai/v1/  → groq
# https://api.together.xyz/v1/     → together
extract_provider_hint() {
    local url="$1"
    local no_proto="${url#https://}"
    no_proto="${no_proto#http://}"
    local domain="${no_proto%%/*}"
    # 去掉常见 TLD 后缀
    local hint="$domain"
    hint="${hint%.com}"
    hint="${hint%.cn}"
    hint="${hint%.xyz}"
    hint="${hint%.io}"
    hint="${hint%.dev}"
    hint="${hint%.net}"
    # 去掉第一个子域名前缀（如 api.、token-plan-cn.）
    if [[ "$hint" == *.* ]]; then
        hint="${hint#*.}"
    fi
    # 取最后一段
    hint="${hint##*.}"
    echo "$hint"
}

# 使用 jq 解析 balance 对象
if command -v jq >/dev/null 2>&1; then
    # 1. 从 settings.json 读取 ANTHROPIC_BASE_URL，推断当前 provider
    base_url=$(resolve_value "ANTHROPIC_BASE_URL")

    provider_name=""
    if [ -n "$base_url" ]; then
        provider_hint=$(extract_provider_hint "$base_url")
        if [ -n "$provider_hint" ]; then
            # 检查 balance 对象中是否有这个 key
            has_key=$(jq -r --arg k "$provider_hint" '(.balance[$k] // null) | type' "$CONFIG_FILE" 2>/dev/null || echo "null")
            if [ "$has_key" = "object" ]; then
                provider_name="$provider_hint"
            fi
        fi
    fi

    # 2. 如果推断失败，fallback 到 balance 对象的第一个 key
    if [ -z "$provider_name" ]; then
        provider_name=$(jq -r '(.balance | keys[0]) // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    fi

    # 2b. SCNet sk-tp 检测：API key 以 sk-tp 开头时路由到 scnet-tp provider
    if [ "$provider_name" = "scnet" ]; then
        scnet_token_env=$(jq -r --arg k "scnet" '.balance[$k].token_env // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [ -n "$scnet_token_env" ]; then
            scnet_token=$(resolve_value "$scnet_token_env")
            if [[ "$scnet_token" == sk-tp* ]]; then
                provider_name="scnet-tp"
            fi
        fi
    fi

    # 3. 获取配置并调用 provider
    if [ -n "$provider_name" ]; then
        token_env=$(jq -r --arg k "$provider_name" '.balance[$k].token_env // empty' "$CONFIG_FILE")
        api_url=$(jq -r --arg k "$provider_name" '.balance[$k].api_url // empty' "$CONFIG_FILE")

        # token_env 为空时仍继续调用（provider 可从文件等其他来源获取凭证）
        token=""
        if [ -n "$token_env" ]; then
            token=$(resolve_value "$token_env")
            if [ -z "$token" ]; then
                exit 0
            fi
        fi

        provider_script="${PROVIDER_DIR}/${provider_name}.sh"
        if [ ! -f "$provider_script" ]; then
            exit 0
        fi

        bash "$provider_script" "$token" "$api_url"
    fi
else
    # jq 不可用，fallback：从 balance 对象中找第一个 key，尝试调用
    # 用 grep 提取 balance 对象中的第一个 key
    first_key=$(grep -o '"balance"[[:space:]]*:[[:space:]]*{' "$CONFIG_FILE" -A 20 2>/dev/null | grep -o '"[a-zA-Z0-9_-]*"[[:space:]]*:' | head -1 | sed 's/"//g;s/[[:space:]]*:$//')
    [ -z "$first_key" ] && exit 0

    token_env=$(grep -o '"token_env"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')

    api_url=$(grep -o '"api_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' || true)

    token=""
    if [ -n "$token_env" ]; then
        token=$(resolve_value "$token_env")
        [ -z "$token" ] && exit 0
    fi

    provider_script="${PROVIDER_DIR}/${first_key}.sh"
    [ -f "$provider_script" ] || exit 0

    bash "$provider_script" "$token" "$api_url"
fi
