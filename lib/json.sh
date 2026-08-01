#!/bin/bash
# JSON 读取模块（awk 实现，不依赖 jq/node）
#
# 背景：项目需在不依赖 jq 的环境下读 JSON。statusline.sh 的配置解析（node
# 不可用时）与 query-balance.sh 的 settings.json 兜底各有一份 grep/sed 实现，
# 本模块收敛为一处。注意：这是慢路径（Windows Git Bash 上约 1 秒/次），
# 性能关键路径应优先走 node 批量提取 + mtime 缓存（见 statusline.sh）。
#
# 用法：source 本文件后调用 json_get <file> <dot.path> <default>
#   json_get config.json "colors.thresholds.green" "55"
#
# 实现说明：原 grep/sed 嵌套解析的花括号匹配不支持嵌套对象（colors 级会把
# 整个文件吞进去导致逐级错乱），awk 版本计数花括号深度并跳过字符串内括号，
# 正确处理任意嵌套。

# 读取 JSON 文件中点号路径的值，未找到返回 default
# 支持嵌套对象路径（逐级查找），简单值与对象均支持
json_get() {
    local file="$1" key_path="$2" default="$3"

    [ -f "$file" ] || { echo "$default"; return; }

    awk -v path="$key_path" -v dflt="$default" '
        BEGIN { n = split(path, keys, ".") }
        { content = content $0 "\n" }
        END {
            cur = content
            for (i = 1; i <= n; i++) {
                k = keys[i]
                # 定位 "key"（带引号搜索，天然防 key 前缀冲突，如 bar vs bar_length）
                idx = index(cur, "\"" k "\"")
                if (idx == 0) { print dflt; exit }
                # 定位冒号
                tail = substr(cur, idx + length(k) + 2)
                colon = index(tail, ":")
                if (colon == 0) { print dflt; exit }
                rest = substr(tail, colon + 1)
                # 跳过空白
                while (substr(rest, 1, 1) == " " || substr(rest, 1, 1) == "\t" || substr(rest, 1, 1) == "\n") rest = substr(rest, 2)
                if (substr(rest, 1, 1) == "{") {
                    # 对象：计数花括号深度（跳过字符串内括号与转义）找配对 }
                    depth = 0; in_str = 0; endpos = 0
                    len = length(rest)
                    for (j = 1; j <= len; j++) {
                        ch = substr(rest, j, 1)
                        if (in_str) {
                            if (ch == "\\") { j++; continue }
                            if (ch == "\"") in_str = 0
                            continue
                        }
                        if (ch == "\"") { in_str = 1; continue }
                        if (ch == "{") depth++
                        else if (ch == "}") {
                            depth--
                            if (depth == 0) { endpos = j; break }
                        }
                    }
                    if (endpos == 0) { print dflt; exit }
                    cur = substr(rest, 1, endpos)
                } else {
                    # 简单值：取到引号外的 , 或 } 为止（引号内逗号属于值，
                    # 如多值 token_env "A,DEEPSEEK_API_KEY" 需完整保留）
                    val = ""
                    in_str = 0
                    len = length(rest)
                    for (j = 1; j <= len; j++) {
                        ch = substr(rest, j, 1)
                        if (in_str) {
                            if (ch == "\\") { j++; continue }
                            if (ch == "\"") in_str = 0
                            val = val ch
                            continue
                        }
                        if (ch == "\"") { in_str = 1; val = val ch; continue }
                        if (ch == "," || ch == "}") break
                        val = val ch
                    }
                    # 清理空白与首尾引号（含 CRLF 的 \r）
                    gsub(/[ \t\r\n]/, "", val)
                    gsub(/^"|"$/, "", val)
                    print val
                    exit
                }
            }
            print dflt
        }
    ' "$file"
}
