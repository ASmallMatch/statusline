#!/bin/bash
# Claude Code StatusLine 主脚本
# 跨平台支持: Windows (Git Bash/WSL), macOS, Linux

set -e

# 读取输入
read -r input || true  # 读 stdin JSON（read 内建替代 cat，零 fork；|| true 防 EOF 触发 set -e）

# 加载布局模块（自举：dev 在 bin/../lib/，安装拍平在同目录）
if [ -f "${BASH_SOURCE[0]%/*}/../lib/layout.sh" ]; then
    source "${BASH_SOURCE[0]%/*}/../lib/layout.sh"
else
    source "${BASH_SOURCE[0]%/*}/layout.sh"
fi
load_module "json.sh"  # node 不可用时的 JSON 慢解析 fallback

CONFIG_FILE="$CONFIG_DIR/config.json"

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
show_tasks=true
show_pr=true
show_git_changes=true
show_effort=true

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
                ["show_tasks",         "panel.show_tasks",          true],
                ["show_pr",            "panel.show_pr",             true],
                ["show_git_changes",   "panel.git.show_git_changes",true],
                ["show_effort",        "panel.show_effort",        true],
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
        # fallback：node 不可用时走 lib/json.sh 慢解析（grep/sed，功能可用）
        green_threshold=$(json_get "$CONFIG_FILE" "colors.thresholds.green" "55")
        yellow_threshold=$(json_get "$CONFIG_FILE" "colors.thresholds.yellow" "75")
        bar_length=$(json_get "$CONFIG_FILE" "bar_length" "10")
        show_git=$(json_get "$CONFIG_FILE" "panel.git.show_git" "true")
        show_time=$(json_get "$CONFIG_FILE" "panel.show_time" "true")
        branch_color=$(json_get "$CONFIG_FILE" "colors.branch" "33")  # 默认橙色(33)
        show_tasks=$(json_get "$CONFIG_FILE" "panel.show_tasks" "true")
        show_pr=$(json_get "$CONFIG_FILE" "panel.show_pr" "true")
        show_git_changes=$(json_get "$CONFIG_FILE" "panel.git.show_git_changes" "true")
        show_effort=$(json_get "$CONFIG_FILE" "panel.show_effort" "true")
    fi
fi

# 获取基本信息
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

# 电池符号: 🀫=满格(麻将牌背) ▣=小格(正极效果) 🀆=空格(麻将白板)
full_block="🀫"
small_block="▣"
empty_block="🀆"

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
    fi
fi

# 颜色定义
c_gray="\033[38;5;245m"      # 灰色
c_cyan="\033[36m"           # 青色
# shellcheck disable=SC2034  # 颜色表保留（当前未用，备用配色）
c_blue="\033[34m"           # 蓝色
c_purple="\033[35m"         # 紫色（Tasks 行）
# shellcheck disable=SC2034
c_white="\033[37m"         # 白色
# shellcheck disable=SC2034
c_dim="\033[2m"             # 暗淡
c_yellow="\033[33m"         # 黄色
c_green="\033[32m"         # 绿色
c_red="\033[31m"           # 红色
reset_color="\033[0m"

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

# Git 信息简化（第二行行首片段，无前导分隔符）
branch_display=""
branch_color_code="\033[${branch_color}m"
if [ "$show_git" = "true" ]; then
    if [ "$has_git" = true ]; then
        branch_display="${branch_color_code} ${branch}${reset_color}"
        # 根据配置决定是否显示文件变动详情
        [ "$show_git_changes" = "true" ] && [ -n "$git_status" ] && branch_display="${branch_display} ${git_status}"
    else
        # 没有 Git 仓库时显示 no-git
        branch_display="${c_gray}no-git${reset_color}"
    fi
fi

# PR 徽章（输入 JSON 的 pr 对象；当前分支无开放 PR 时字段缺席，整段不显示）
pr_display=""
if [ "$show_pr" = "true" ]; then
    case "$input" in
        *'"pr":{"number":'*)
            pr_number="${input#*\"pr\":{\"number\":}"
            pr_number="${pr_number%%[!0-9]*}"
            # 评审状态（pr 存在时也可能独立缺席）
            pr_state=""
            case "$input" in
                *'"review_state":"'*)
                    pr_state="${input#*\"review_state\":\"}"
                    pr_state="${pr_state%%\"*}"
                    ;;
            esac
            case "$pr_state" in
                approved)          pr_icon=" ✓"; pr_color="$c_green"  ;;
                changes_requested) pr_icon=" ✗"; pr_color="$c_red"    ;;
                pending)           pr_icon=" …"; pr_color="$c_yellow" ;;
                draft)             pr_icon=" ✎"; pr_color="$c_gray"   ;;
                *)                 pr_icon="";    pr_color="$c_gray"  ;;
            esac
            if [ -n "$pr_number" ]; then
                pr_text="#${pr_number}${pr_icon}"
                # OSC 8 可点击链接（iTerm2/Kitty/WezTerm 等支持；不支持的终端静默忽略）
                case "$input" in
                    *'"url":"http'*)
                        pr_url="${input#*\"url\":\"}"
                        pr_url="${pr_url%%\"*}"
                        case "$pr_url" in
                            http*) pr_text="\033]8;;${pr_url}\033\\${pr_text}\033]8;;\033\\" ;;
                        esac
                        ;;
                esac
                pr_display="${pr_color}${pr_text}${reset_color}"
            fi
            ;;
    esac
fi

# 时间（只显示时间，省略日期）
time_display=""
if [ "$show_time" = "true" ]; then
    time_now=$(printf '%(%H:%M)T' -1 2>/dev/null || date +%H:%M 2>/dev/null || echo "")
    case "$time_now" in ""|*T*|*'%'*) time_now=$(date +%H:%M 2>/dev/null || echo "") ;; esac
    [ -n "$time_now" ] && time_display=" ${sep} ${c_gray}${time_now}${reset_color}"
fi

# 获取 session_id（Tasks 目录命名用）
session_id=""
case "$input" in
    *'"session_id":"'*)
        session_id="${input#*\"session_id\":\"}"
        session_id="${session_id%%\"*}"
        ;;
esac

# ========== Tasks 计数（TaskCreate 任务系统）==========
# 任务持久化在 <claude 配置目录>/tasks/session-<session_id 前 8 位>/<n>.json，
# 逐个 bash 内建读入（$(<file) 不 exec 外部命令），统计 completed/total。
# 会话未用过 TaskCreate 时目录不存在，整段不显示。
tasks_line=""
if [ "$show_tasks" = "true" ] && [ -n "$session_id" ]; then
    tasks_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/tasks/session-${session_id:0:8}"
    if [ -d "$tasks_dir" ]; then
        tasks_total=0; tasks_done=0
        for _tf in "$tasks_dir"/*.json; do
            [ -f "$_tf" ] || continue  # 无匹配时 glob 保留字面量
            tasks_total=$((tasks_total + 1))
            case "$(<"$_tf")" in
                *\"status\":\ \"completed\"*|*\"status\":\"completed\"*) tasks_done=$((tasks_done + 1)) ;;
            esac
        done
        [ "$tasks_total" -gt 0 ] && tasks_line="❦ Tasks  ${tasks_done}/${tasks_total}"
    fi
fi

# ========== 余额查询（stale-while-revalidate）==========
# 同步路径直接读统一缓存文件（read 内建，零 fork、零等待），后台异步触发
# 调度器刷新。节流标记避免高频刷新时反复 spawn 调度器（调度器内部另有
# provider 层 5min TTL，控制是否真发网络请求）。
balance_display=""
# 查找 query-balance.sh 调度器（lib/layout.sh 统一双布局定位）
balance_script=$(find_file "query-balance.sh" 2>/dev/null || true)

BALANCE_CACHE="$CACHE_DIR/balance_current.txt"
BALANCE_MARKER="$CACHE_DIR/balance_refresh.marker"
BALANCE_REFRESH_TTL=300  # 与 provider 缓存对齐，5 分钟内不重复 spawn 调度器

# 同步路径：直接读统一缓存（read 内建，零 fork、零等待）
if [ -f "$BALANCE_CACHE" ]; then
    balance_result=""
    read -r balance_result < "$BALANCE_CACHE" 2>/dev/null || true
    [ -n "$balance_result" ] && balance_display="${c_gray}⟦${reset_color}${balance_result}${c_gray}⟧${reset_color}"
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
        ) >/dev/null 2>&1 &
        printf '%s' "$_now" > "$BALANCE_MARKER"
    fi
fi

# ========== 输出生成 ==========
# 百分比直接显示普通数字（不依赖任何特殊字体）
used_pct_disp="$used_pct"

# 进度条显示
progress_display="${bar_color}❦ ${progress_bar} ${used_pct_disp}${reset_color}"

# 思考级别显示（‹费用›‹high› ↯；字段缺失或关闭时整段不显示）
effort_display=""
if [ -n "$effort" ] && [ "$show_effort" = "true" ]; then
    case "$effort" in
        low)        effort_color="$c_gray"    ;;  # 低思考：低调灰
        medium)     effort_color="$c_green"   ;;  # 中思考：绿
        high)       effort_color="$c_yellow"  ;;  # 高思考：黄
        xhigh|max)  effort_color="$c_red"     ;;  # 极高/最大思考：红
        *)          effort_color="$c_gray"    ;;
    esac
    effort_display="${c_gray}⟦${reset_color}${effort_color}${effort}${reset_color}${c_gray}⟧${reset_color}"
fi

# 分支 · PR 段（两者可独立缺席，都为空时第一行不插入分支片段）
git_line=""
[ -n "$branch_display" ] && git_line="$branch_display"
if [ -n "$pr_display" ]; then
    if [ -n "$git_line" ]; then
        git_line="${git_line} ${sep} ${pr_display}"
    else
        git_line="$pr_display"
    fi
fi

# 第一行: 进度条 · 余额 · 思考级别 · 分支/PR · 时间（余额/思考/分支为空时跳过对应片段与分隔符）
statusline="${progress_display}"
[ -n "$balance_display" ] && statusline="${statusline} ${sep} ${balance_display}"
[ -n "$effort_display" ] && statusline="${statusline} ${effort_display}"
[ -n "$git_line" ] && statusline="${statusline} ${sep} ${git_line}"
statusline="${statusline}${time_display}"

# 活动行前缀
activity_prefix="  "

# 输出主状态行
echo -e "${statusline}"

# 输出第二行（路径）与第三行（Tasks）
[ -n "$dir_display" ] && echo -e "${activity_prefix}${c_gray}↯${reset_color} ${dir_display}"
[ -n "$tasks_line" ] && echo -e "${activity_prefix}${c_purple}${tasks_line}${reset_color}"

exit 0
