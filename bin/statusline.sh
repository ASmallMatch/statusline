#!/bin/bash
# Claude Code StatusLine 主脚本
# 跨平台支持: Windows (Git Bash/WSL), macOS, Linux

set -e

# 读取输入
read -r input || true  # 读 stdin JSON（read 内建替代 cat，零 fork；|| true 防 EOF 触发 set -e）

# 配置目录
CONFIG_DIR="${CLAUDE_STATUSLINE_DIR:-$HOME/.claude/statusline}"
CONFIG_FILE="$CONFIG_DIR/config.json"
CACHE_DIR="$CONFIG_DIR/cache"

# 脚本所在目录（用于开发模式下定位资源）
SCRIPT_DIR_STATUSLINE="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"  # dirname 用参数扩展，省一次 fork

# 解析配置（简单解析，不依赖 jq）
# 支持嵌套路径，如 "colors.thresholds.green"
parse_config() {
    local key_path="$1"
    local default="$2"

    if [ -f "$CONFIG_FILE" ]; then
        # 读取整个文件内容
        local config_content=$(cat "$CONFIG_FILE" 2>/dev/null)

        # 将路径按.分割，逐级查找
        local keys=$(echo "$key_path" | tr '.' '\n')
        local current="$config_content"
        local found=true

        for key in $keys; do
            # 在当前层级查找 key
            local pattern="\"$key\"[[:space:]]*:[[:space:]]*"
            if echo "$current" | grep -q "$pattern"; then
                # 提取该 key 的值部分
                local value=$(echo "$current" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*[^,}]*" | head -1)
                if [ -n "$value" ]; then
                    # 获取值后的内容（可能是对象或简单值）
                    local after_key=$(echo "$value" | sed "s/\"$key\"[[:space:]]*:[[:space:]]*//")

                    # 如果是对象（以{开头），在 current 中查找该对象的内容
                    if echo "$after_key" | grep -q '^\s*{'; then
                        # 提取对象内容（需要匹配花括号）
                        local obj_start=$(echo "$current" | grep -b -o "\"$key\"[[:space:]]*:[[:space:]]*{" | head -1 | cut -d: -f1)
                        if [ -n "$obj_start" ]; then
                            # 从对象开始位置提取，尝试匹配花括号
                            local obj_content=$(echo "$current" | tail -c +$((obj_start + 1)))
                            # 简单匹配：找到第一个完整的 {...}
                            # 使用 sed 匹配花括号对
                            current=$(echo "$obj_content" | sed 's/[^{]*\({\).*/\1/; :a; N; s/\n//; ta' | head -c 1000 | sed 's/^{\([^{}]*\)}.*/\1/')
                        else
                            found=false
                            break
                        fi
                    else
                        # 简单值，直接使用
                        current="$after_key"
                    fi
                else
                    found=false
                    break
                fi
            else
                found=false
                break
            fi
        done

        if [ "$found" = true ] && [ -n "$current" ]; then
            # 清理值（去掉引号）
            echo "$current" | sed 's/^"//;s/"$//' | tr -d '[:space:]'
            return
        fi
    fi

    echo "$default"
}

# 读取配置
# 性能要点：原 parse_config 用 grep/sed 管道解析 JSON，在 Windows Git Bash 上每次
# 调用约 1 秒（fork 子进程开销大），10 次调用累计 ~8.6 秒，是状态栏启动慢的元凶。
# 改为一次 node 调用批量提取所有字段（~60ms）；node 不可用时 fallback 到 parse_config。
green_threshold=55
yellow_threshold=75
bar_length=10
show_git=true
show_time=true
branch_color=33
show_tools=true
show_agents=true
show_todos=true
show_git_changes=true
show_effort=true
digit_style=segment

_config_cache="$CACHE_DIR/config_parsed.sh"
_need_parse=true
# 命中缓存（config.json 未比缓存新）：source 零 fork，跳过 node 启动
if [ -f "$_config_cache" ] && [ ! "$CONFIG_FILE" -nt "$_config_cache" ]; then
    # shellcheck disable=SC1090
    source "$_config_cache" 2>/dev/null && _need_parse=false
fi

if [ "$_need_parse" = true ]; then
    if [ -f "$CONFIG_FILE" ] && command -v node >/dev/null 2>&1; then
        # 一次 node 调用提取全部字段，输出 name="value" 供 eval 注入
        _config_parsed=$(node -e '
            const fs = require("fs");
            let cfg = {};
            try { cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch {}
            const get = (p, d) => {
                let v = p.split(".").reduce((o, k) => (o == null ? o : o[k]), cfg);
                return v == null ? d : v;
            };
            const fields = [
                ["green_threshold",    "colors.thresholds.green",   55],
                ["yellow_threshold",   "colors.thresholds.yellow",  75],
                ["bar_length",         "bar_length",                10],
                ["show_git",           "panel.git.show_git",        true],
                ["show_time",          "panel.show_time",           true],
                ["branch_color",       "colors.branch",             "33"],
                ["show_tools",         "panel.show_tools",          true],
                ["show_agents",        "panel.show_agents",         true],
                ["show_todos",         "panel.show_todos",          true],
                ["show_git_changes",   "panel.git.show_git_changes",true],
                ["show_effort",        "panel.show_effort",        true],
                ["digit_style",        "panel.digit_style",        "segment"],
            ];
            for (const [name, path, dflt] of fields) {
                process.stdout.write(name + "=" + JSON.stringify(String(get(path, dflt))) + "\n");
            }
        ' "$CONFIG_FILE" 2>/dev/null || true)
        if [ -n "$_config_parsed" ]; then
            eval "$_config_parsed"
            mkdir -p "$CACHE_DIR"
            printf '%s\n' "$_config_parsed" > "$_config_cache"
        fi
    else
        # fallback：node 不可用时走原解析（慢，但功能可用）
        green_threshold=$(parse_config "colors.thresholds.green" "55")
        yellow_threshold=$(parse_config "colors.thresholds.yellow" "75")
        bar_length=$(parse_config "bar_length" "10")
        show_git=$(parse_config "panel.git.show_git" "true")
        show_time=$(parse_config "panel.show_time" "true")
        branch_color=$(parse_config "colors.branch" "33" | tr -d '"')  # 默认橙色(33)，确保去掉引号
        show_tools=$(parse_config "panel.show_tools" "true")
        show_agents=$(parse_config "panel.show_agents" "true")
        show_todos=$(parse_config "panel.show_todos" "true")
        show_git_changes=$(parse_config "panel.git.show_git_changes" "true")
        show_effort=$(parse_config "panel.show_effort" "true")
        digit_style=$(parse_config "panel.digit_style" "segment")
    fi
fi

# 获取基本信息
username="${USERNAME:-${USER:-$(whoami 2>/dev/null || echo user)}}"  # 常态零 fork；USERNAME/USER 都缺才 fallback whoami
# 参数扩展提取 cwd（零 fork，替代 echo|grep|cut）
full_path="${input#*\"cwd\":\"}"
full_path="${full_path%%\"*}"
[ -z "$full_path" ] && full_path="$PWD"

# 直接使用输入的 used_percentage
used_pct="${input#*\"used_percentage\":}"
used_pct="${used_pct%%[!0-9]*}"
[ -z "$used_pct" ] && used_pct="0"

# 思考级别 effort.level（模型不支持 effort 参数时字段缺失，case 守卫兜底为空）
effort="${input#*\"effort\":{\"level\":\"}"
effort="${effort%%\"*}"
case "$effort" in
    low|medium|high|xhigh|max) ;;
    *) effort="" ;;
esac

# 颜色判断
if [ "$used_pct" -lt "$green_threshold" ] 2>/dev/null; then
    bar_color="\033[32m"      # 绿色
elif [ "$used_pct" -le "$yellow_threshold" ] 2>/dev/null; then
    bar_color="\033[33m"      # 黄色
else
    bar_color="\033[31m"      # 红色
fi

# 生成电池风格进度条
# 计算总点数 (每格100点)
total_points=$((used_pct * bar_length))
full_cells=$((total_points / 100))
remainder=$((total_points % 100))

# 电池符号: ■=满格 •=小格(正极效果) □=空格
full_block="■"
small_block="•"
empty_block="□"

progress_bar=""
i=0

# 先显示小格（正极在最前面），所有情况都显示包括0%
if [ $i -lt $bar_length ]; then
    progress_bar="${small_block}"
    i=$((i + 1))
fi

# 填充满格（小格已经占了一格位置，所以满格数不变，但总长度要减1）
filled_count=0
while [ $filled_count -lt $full_cells ] && [ $i -lt $bar_length ]; do
    progress_bar="${progress_bar}${full_block}"
    i=$((i + 1))
    filled_count=$((filled_count + 1))
done

# 填充空格
while [ $i -lt $bar_length ]; do
    progress_bar="${progress_bar}${empty_block}"
    i=$((i + 1))
done

# Git 信息（一次调用拿到仓库检查 + 分支 + 变动统计，替代原 rev-parse+branch+status 三次调用）
git_info=""
has_git=false
branch=""
git_status=""
if [ "$show_git" = "true" ]; then
    git_out=$(git -C "$full_path" -c core.fileMode=false status --porcelain -b 2>/dev/null || true)
    if [ -n "$git_out" ]; then
        has_git=true
        # 首行 ## <branch> 解析分支名（参数扩展，无 fork）
        branch_line="${git_out%%$'\n'*}"
        case "$branch_line" in
            "## "*"no branch"*) branch="detached" ;;
            *"No commits yet on "*) branch="${branch_line##* on }" ;;
            "## "*)
                branch="${branch_line#?? }"
                branch="${branch%%...*}"
                branch="${branch%% *}"
                ;;
            *) branch="detached" ;;
        esac
        [ -z "$branch" ] && branch="detached"

        # 后续行解析变动统计（while read + case 内建，无 fork）
        # Git 符号: +=新增 -=删除 ~=修改 ✓=暂存
        added=0; modified=0; deleted=0; staged=0
        while IFS= read -r line; do
            case "$line" in
                "## "*|"") ;;
                "?? "*) added=$((added + 1)) ;;
                " M "*) modified=$((modified + 1)) ;;
                " D "*) deleted=$((deleted + 1)) ;;
                [AM]?*) staged=$((staged + 1)) ;;
            esac
        done <<< "$git_out"

        # 构建状态字符串（过滤掉 0 值）
        [ "$added" -ne 0 ] 2>/dev/null && git_status="${git_status}+${added} "
        [ "$modified" -ne 0 ] 2>/dev/null && git_status="${git_status}~${modified} "
        [ "$deleted" -ne 0 ] 2>/dev/null && git_status="${git_status}-${deleted} "
        [ "$staged" -ne 0 ] 2>/dev/null && git_status="${git_status}✓${staged} "
        git_status="${git_status% }"
        git_info="${branch}${git_status}"
    fi
fi

# 颜色定义
c_gray="\033[38;5;245m"      # 灰色
c_cyan="\033[36m"           # 青色
c_blue="\033[34m"           # 蓝色
c_purple="\033[35m"         # 紫色
c_white="\033[37m"         # 白色
c_dim="\033[2m"             # 暗淡
c_yellow="\033[33m"         # 黄色
c_green="\033[32m"         # 绿色
c_red="\033[31m"           # 红色
reset_color="\033[0m"

# transcript 活动行计数由 node 输出 key=value，bash while read 内建解析（见 Transcript 解析块）

# 显示两级目录名（如：parent/current）
get_two_level_path() {
    local path="$1"
    # 移除末尾的斜杠
    path="${path%/}"
    # 根目录特殊情况
    [ -z "$path" ] && path="/"
    # basename / dirname 用参数扩展（零 fork，替代 basename/dirname 外部命令）
    local current="${path##*/}"
    local parent="${path%/*}"
    parent="${parent##*/}"
    # 如果当前是根目录
    [ "$current" = "/" ] && current="root"
    # 如果父目录是根目录或空，只显示当前目录
    if [ "$parent" = "/" ] || [ -z "$parent" ] || [ "$parent" = "$path" ]; then
        echo "$current"
    else
        echo "${parent}/${current}"
    fi
}
display_path=$(get_two_level_path "$full_path")

# 路径着色
dir_display="${c_cyan}${display_path}${reset_color}"

# 分隔符
sep="${c_gray}▸${reset_color}"

# Git 信息简化
branch_display=""
branch_color_code="\033[${branch_color}m"
if [ "$show_git" = "true" ]; then
    if [ "$has_git" = true ]; then
        # 根据配置决定是否显示文件变动详情
        if [ "$show_git_changes" = "true" ] && [ -n "$git_status" ]; then
            branch_display=" ${sep} ${branch_color_code} ${branch}${reset_color} ${git_status}"
        else
            branch_display=" ${sep} ${branch_color_code} ${branch}${reset_color}"
        fi
    else
        # 没有 Git 仓库时显示 no-git
        branch_display=" ${sep} ${c_gray}no-git${reset_color}"
    fi
fi

# 时间（只显示时间，省略日期）
time_display=""
if [ "$show_time" = "true" ]; then
    time_now=$(printf '%(%H:%M)T' -1 2>/dev/null || date +%H:%M 2>/dev/null || echo "")
    case "$time_now" in ""|*T*|*'%'*) time_now=$(date +%H:%M 2>/dev/null || echo "") ;; esac
    [ -n "$time_now" ] && time_display=" ${sep} ${c_gray}${time_now}${reset_color}"
fi

# ========== Transcript 解析 ==========
# 获取 transcript 路径
transcript_path=""
case "$input" in
    *'"transcript_path":"'*)
        transcript_path="${input#*\"transcript_path\":\"}"
        transcript_path="${transcript_path%%\"*}"
        ;;
esac

# 初始化活动行
tools_line=""
agents_line=""
todos_line=""

# 解析 transcript（如果路径存在且 Node.js 可用）
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ] && command -v node >/dev/null 2>&1; then
    # 优先使用项目目录的解析器（开发模式），否则使用 CONFIG_DIR 中的
    if [ -f "${SCRIPT_DIR_STATUSLINE}/../scripts/transcript-parser-lite.js" ]; then
        parser_script="${SCRIPT_DIR_STATUSLINE}/../scripts/transcript-parser-lite.js"
    elif [ -f "${SCRIPT_DIR_STATUSLINE}/transcript-parser-lite.js" ]; then
        parser_script="${SCRIPT_DIR_STATUSLINE}/transcript-parser-lite.js"
    else
        parser_script="${CONFIG_DIR}/transcript-parser-lite.js"
    fi
    if [ -f "$parser_script" ]; then
        transcript_data=$(node "$parser_script" "$transcript_path" 2>/dev/null)

        if [ -n "$transcript_data" ]; then
            # node 输出 key=value，while read 内建解析（零 fork，替代原 parse_* 的 grep）
            tools_running=0; agents_running=0; todos_ip=0; todos_total=0
            while IFS='=' read -r _k _v; do
                case "$_k" in
                    tools_running) tools_running="${_v}" ;;
                    agents_running) agents_running="${_v}" ;;
                    todos_in_progress) todos_ip="${_v}" ;;
                    todos_total) todos_total="${_v}" ;;
                esac
            done <<< "$transcript_data"
            [ "$show_tools" = "true" ] && [ "$tools_running" -gt 0 ] 2>/dev/null && tools_line="❦ Tools  ${tools_running} running"
            [ "$show_agents" = "true" ] && [ "$agents_running" -gt 0 ] 2>/dev/null && agents_line="❦ Agents ${agents_running} running"
            [ "$show_todos" = "true" ] && [ "$todos_ip" -gt 0 ] 2>/dev/null && todos_line="❦ Todos  ${todos_ip}/${todos_total}"
        fi
    fi
fi

# ========== 余额查询（stale-while-revalidate）==========
# 同步路径直接读统一缓存文件（read 内建，零 fork、零等待），后台异步触发
# 调度器刷新。节流标记避免高频刷新时反复 spawn 调度器（调度器内部另有
# provider 层 5min TTL，控制是否真发网络请求）。
balance_display=""
# 查找 query-balance.sh 调度器
if [ -f "${SCRIPT_DIR_STATUSLINE}/query-balance.sh" ]; then
    balance_script="${SCRIPT_DIR_STATUSLINE}/query-balance.sh"
elif [ -f "${SCRIPT_DIR_STATUSLINE}/../bin/query-balance.sh" ]; then
    balance_script="${SCRIPT_DIR_STATUSLINE}/../bin/query-balance.sh"
elif [ -f "${CONFIG_DIR}/query-balance.sh" ]; then
    balance_script="${CONFIG_DIR}/query-balance.sh"
fi

BALANCE_CACHE="$CACHE_DIR/balance_current.txt"
BALANCE_MARKER="$CACHE_DIR/balance_refresh.marker"
BALANCE_REFRESH_TTL=300  # 与 provider 缓存对齐，5 分钟内不重复 spawn 调度器

# 同步路径：直接读统一缓存（read 内建，零 fork、零等待）
if [ -f "$BALANCE_CACHE" ]; then
    balance_result=""
    read -r balance_result < "$BALANCE_CACHE" 2>/dev/null || true
    [ -n "$balance_result" ] && balance_display="${c_gray}[${reset_color}${balance_result}${c_gray}]${reset_color}"
fi

# 后台异步刷新（节流：TTL 内不重复 spawn）。用 printf/read 内建取时间，避免 fork
if [ -n "$balance_script" ] && [ -f "$balance_script" ]; then
    _now=$(printf '%(%s)T' -1 2>/dev/null || date +%s)
    _last_refresh_epoch=0
    if [ -f "$BALANCE_MARKER" ]; then
        read -r _last_refresh_epoch < "$BALANCE_MARKER" 2>/dev/null || true
    fi
    case "$_last_refresh_epoch" in ''|*[!0-9]*) _last_refresh_epoch=0 ;; esac
    if [ $((_now - _last_refresh_epoch)) -ge "$BALANCE_REFRESH_TTL" ] 2>/dev/null; then
        mkdir -p "$CACHE_DIR"
        # 后台刷新，原子写（tmp + mv），失败不污染缓存
        (
            _tmp="${BALANCE_CACHE}.tmp.$$"
            if bash "$balance_script" > "$_tmp" 2>/dev/null && [ -s "$_tmp" ]; then
                mv "$_tmp" "$BALANCE_CACHE"
            else
                rm -f "$_tmp"
            fi
        ) &
        printf '%s' "$_now" > "$BALANCE_MARKER"
    fi
fi

# ========== 输出生成 ==========
# 数字映射（panel.digit_style 控制）：
#   segment  = 数码管 U+1FBF0-U+1FBF9（7 段显示字符，需终端字体支持，见 fonts/ 与 README）
#   subscript= 下标数字（通用，任何终端可显示）
segment_digits() {
    local s="$1" out="" c
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        case "$c" in
            0) out="${out}🯰" ;; 1) out="${out}🯱" ;; 2) out="${out}🯲" ;; 3) out="${out}🯳" ;;
            4) out="${out}🯴" ;; 5) out="${out}🯵" ;; 6) out="${out}🯶" ;; 7) out="${out}🯷" ;;
            8) out="${out}🯸" ;; 9) out="${out}🯹" ;; *) out="${out}${c}" ;;
        esac
    done
    printf '%s' "$out"
}

subscript_digits() {
    local s="$1"
    s="${s//0/₀}"; s="${s//1/₁}"; s="${s//2/₂}"; s="${s//3/₃}"; s="${s//4/₄}"
    s="${s//5/₅}"; s="${s//6/₆}"; s="${s//7/₇}"; s="${s//8/₈}"; s="${s//9/₉}"
    printf '%s' "$s"
}

case "$digit_style" in
    segment) used_pct_disp=$(segment_digits "$used_pct") ;;
    *)       used_pct_disp=$(subscript_digits "$used_pct") ;;  # 其他值/旧版本回退下标，保证可显示
esac

# 进度条显示
progress_display="${bar_color}❦ ${progress_bar}${used_pct_disp}${reset_color}"

# 思考级别显示（[费用][high] ↯；字段缺失或关闭时整段不显示）
effort_display=""
if [ -n "$effort" ] && [ "$show_effort" = "true" ]; then
    case "$effort" in
        low)        effort_color="$c_gray"    ;;  # 低思考：低调灰
        medium)     effort_color="$c_green"   ;;  # 中思考：绿
        high)       effort_color="$c_yellow"  ;;  # 高思考：黄
        xhigh|max)  effort_color="$c_red"     ;;  # 极高/最大思考：红
        *)          effort_color="$c_gray"    ;;
    esac
    effort_display="${c_gray}[${reset_color}${effort_color}${effort}${reset_color}${c_gray}]${reset_color}"
fi

# 第一行: 进度条 · 余额 · 思考级别 · 路径 · 分支 · 时间
statusline="${progress_display}${balance_display}${effort_display} ${c_gray}↯${reset_color} ${dir_display}${branch_display}${time_display}"

# 主状态行前缀
main_prefix=""
# 活动行前缀
activity_prefix="  "

# 输出主状态行
echo -e "${statusline}"

# 输出活动行（如果有）
[ -n "$tools_line" ] && echo -e "${activity_prefix}${c_yellow}${tools_line}${reset_color}"
[ -n "$agents_line" ] && echo -e "${activity_prefix}${c_cyan}${agents_line}${reset_color}"
[ -n "$todos_line" ] && echo -e "${activity_prefix}${c_green}${todos_line}${reset_color}"

exit 0
