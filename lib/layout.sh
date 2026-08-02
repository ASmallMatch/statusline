#!/bin/bash
# 布局模块：统一"开发布局 vs 安装布局"的资源定位
#
# 背景：项目在两种布局下运行
#   - 开发布局：bin/ scripts/ config/ lib/ 分目录（仓库内）
#   - 安装布局：install.sh 复制到 ~/.claude/statusline/，多数文件拍平到根，
#     providers/ 与 scripts/ 保留子目录
# 曾有三个脚本各自实现一套多路 fallback 查找（5 处重复），本模块收敛为一处。
#
# 用法：脚本顶部 source 本文件（source 路径约定）：
#   - 开发布局（脚本在 bin/ 下）：source "${BASH_SOURCE[0]%/*}/../lib/layout.sh"
#   - 安装布局（脚本与 layout.sh 同目录，拍平到根）：source "${BASH_SOURCE[0]%/*}/layout.sh"
# 然后可直接使用 LAYOUT_ROOT/CONFIG_DIR/CACHE_DIR，或调用 find_file/find_dir。
# 本文件内全部为 bash 内建操作，零 fork（一次启动时的 $() 除外）。

# 自定位：layout.sh 在布局根的 lib/ 子目录（开发），或布局根本身（安装拍平）
# 性能要点：安装布局下 source 到的是绝对路径，全参数扩展零 fork；
# 仅开发布局（相对路径或残留 ../）才用子 shell cd 归一化，非性能关键路径。
LAYOUT_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
case "$LAYOUT_SCRIPT_DIR" in
    /*|?:/*) ;;
    *) LAYOUT_SCRIPT_DIR="$(cd "$LAYOUT_SCRIPT_DIR" && pwd)" ;;
esac
case "$LAYOUT_SCRIPT_DIR" in
    */lib) LAYOUT_ROOT="${LAYOUT_SCRIPT_DIR%/lib}" ;;
    *)     LAYOUT_ROOT="$LAYOUT_SCRIPT_DIR" ;;
esac
# 绝对路径里残留 ../（如 bash /abs/bin/install.sh 时 source 到 bin/../lib/layout.sh）再归一化
case "$LAYOUT_ROOT" in
    *"/../"*|*/..) LAYOUT_ROOT="$(cd "$LAYOUT_ROOT" && pwd)" ;;
esac

# 配置目录（环境变量可覆盖，与 install.sh 的 DEFAULT_INSTALL_DIR 约定一致）
CONFIG_DIR="${CLAUDE_STATUSLINE_DIR:-$HOME/.claude/statusline}"
CACHE_DIR="$CONFIG_DIR/cache"

# 搜索前缀：安装布局文件拍平到根；开发布局分布在 bin/ scripts/ lib/ config/
# 顺序 = 根优先（安装布局命中即止），然后开发布局各目录
_layout_prefixes=( "" "bin/" "scripts/" "lib/" "config/" )

# 按文件名查找文件：find_file <name>，输出完整路径，命中返回 0，未命中返回 1
find_file() {
    local name="$1" prefix
    for prefix in "${_layout_prefixes[@]}"; do
        if [ -f "$LAYOUT_ROOT/$prefix$name" ]; then
            printf '%s\n' "$LAYOUT_ROOT/$prefix$name"
            return 0
        fi
    done
    return 1
}

# 按目录名查找目录：find_dir <name>，输出完整路径，命中返回 0，未命中返回 1
find_dir() {
    local name="$1" prefix
    for prefix in "${_layout_prefixes[@]}"; do
        if [ -d "$LAYOUT_ROOT/$prefix$name" ]; then
            printf '%s\n' "$LAYOUT_ROOT/$prefix$name"
            return 0
        fi
    done
    return 1
}

# 加载 lib/ 下的共享模块：load_module <name>（如 json.sh）
# 安装布局模块拍平到根，开发布局在 lib/ 子目录，两处均可 source
load_module() {
    local m="$1"
    if [ -f "$LAYOUT_ROOT/$m" ]; then
        source "$LAYOUT_ROOT/$m"
    elif [ -f "$LAYOUT_ROOT/lib/$m" ]; then
        source "$LAYOUT_ROOT/lib/$m"
    fi
}
