#!/bin/bash
# Claude Code Statusline 安装脚本
# 支持安装到 user 级别

# 不设置 set -e，改为手动处理错误，防止窗口自动关闭
# set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 加载布局模块，导出 LAYOUT_ROOT（开发布局 = 项目根）与 find_file 等
source "$SCRIPT_DIR/../lib/layout.sh"
# 目录同源：项目根由 lib/layout.sh 推导，与运行时查找使用同一来源
PROJECT_ROOT="$LAYOUT_ROOT"

# 默认安装路径
DEFAULT_INSTALL_DIR="$HOME/.claude/statusline"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 暂停等待用户按键（非交互环境如 CI 自动跳过，避免 /dev/tty 报错）
pause() {
    echo ""
    if [ -t 0 ]; then
        echo -n "按任意键继续..."
        read -n 1 -s < /dev/tty 2>/dev/null || read -n 1 -s
        echo ""
    fi
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
Claude Code Statusline 安装脚本

用法: bash bin/install.sh [选项]

选项:
    -h, --help          显示帮助信息
    -d, --dir DIR       指定安装目录 (默认: ~/.claude/statusline)
    -u, --uninstall     卸载 statusline
    -c, --check         检查安装状态

示例:
    bash bin/install.sh                    # 安装到默认目录
    bash bin/install.sh -d /custom/path    # 安装到自定义目录
    bash bin/install.sh -u                 # 卸载
    bash bin/install.sh -c                 # 检查安装状态

EOF
}

# 检查依赖
check_dependencies() {
    print_info "检查依赖..."

    # 检查 bash
    if ! command -v bash &> /dev/null; then
        print_error "需要 bash 环境"
        exit 1
    fi

    # 检查 git (用于 Git 状态显示)
    if ! command -v git &> /dev/null; then
        print_warning "未检测到 git，Git 状态显示功能将不可用"
    fi

    print_success "依赖检查通过"
}

# 创建安装目录
create_install_dir() {
    local install_dir="$1"

    print_info "创建安装目录: $install_dir"

    if [ -d "$install_dir" ]; then
        print_warning "目录已存在，将备份现有配置"
        backup_dir="${install_dir}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -r "$install_dir" "$backup_dir"
        print_info "已备份到: $backup_dir"

        # 保留 cache 目录 (存有 provider Cookie、余额缓存等运行时状态)
        # 先移出 cache，再清空目录，最后移回，避免 rm -rf 误删登录态
        cache_preserved=""
        if [ -d "$install_dir/cache" ]; then
            cache_preserved="${TMPDIR:-/tmp}/statusline_cache_preserved.$$"
            rm -rf "$cache_preserved" 2>/dev/null || true
            mv "$install_dir/cache" "$cache_preserved"
        fi

        rm -rf "$install_dir"

        if [ -n "$cache_preserved" ] && [ -d "$cache_preserved" ]; then
            mkdir -p "$install_dir"
            mv "$cache_preserved" "$install_dir/cache"
        fi
    fi

    mkdir -p "$install_dir/providers"
    mkdir -p "$install_dir/scripts"
    print_success "安装目录创建成功"
}

# 复制文件
copy_files() {
    local install_dir="$1"

    print_info "复制文件..."

    # 复制主脚本
    cp "$SCRIPT_DIR/statusline.sh" "$install_dir/"
    chmod +x "$install_dir/statusline.sh"

    # 复制余额查询调度器
    if [ -f "$SCRIPT_DIR/query-balance.sh" ]; then
        cp "$SCRIPT_DIR/query-balance.sh" "$install_dir/"
        chmod +x "$install_dir/query-balance.sh"
    elif [ -f "$PROJECT_ROOT/bin/query-balance.sh" ]; then
        cp "$PROJECT_ROOT/bin/query-balance.sh" "$install_dir/"
        chmod +x "$install_dir/query-balance.sh"
    fi

    # 复制配置文件
    cp "$PROJECT_ROOT/config/config.json" "$install_dir/"

    # 复制布局与 JSON 模块（拍平到安装目录根，供 statusline.sh/query-balance.sh source）
    cp "$LAYOUT_ROOT/lib/layout.sh" "$install_dir/"
    cp "$LAYOUT_ROOT/lib/json.sh" "$install_dir/"

    # 复制 provider 脚本
    if [ -d "$PROJECT_ROOT/config/providers" ]; then
        cp "$PROJECT_ROOT/config/providers/"*.sh "$install_dir/providers/" 2>/dev/null || true
        chmod +x "$install_dir/providers/"*.sh 2>/dev/null || true
    fi

    # 复制 MiMo cookie 刷新脚本
    if [ -f "$PROJECT_ROOT/scripts/refresh-xiaomimimo-cookie.js" ]; then
        cp "$PROJECT_ROOT/scripts/refresh-xiaomimimo-cookie.js" "$install_dir/scripts/"
    fi
    if [ -f "$PROJECT_ROOT/scripts/refresh-xiaomimimo-cookie.sh" ]; then
        cp "$PROJECT_ROOT/scripts/refresh-xiaomimimo-cookie.sh" "$install_dir/scripts/"
        chmod +x "$install_dir/scripts/refresh-xiaomimimo-cookie.sh"
    fi

    # 复制火山方舟 cookie 刷新脚本
    if [ -f "$PROJECT_ROOT/scripts/refresh-volces-cookie.js" ]; then
        cp "$PROJECT_ROOT/scripts/refresh-volces-cookie.js" "$install_dir/scripts/"
    fi
    if [ -f "$PROJECT_ROOT/scripts/refresh-volces-cookie.sh" ]; then
        cp "$PROJECT_ROOT/scripts/refresh-volces-cookie.sh" "$install_dir/scripts/"
        chmod +x "$install_dir/scripts/refresh-volces-cookie.sh"
    fi

    print_success "文件复制完成"
}

# 安装 cookie 刷新脚本依赖（MiMo 与火山方舟共用 Playwright）
install_cookie_refresh_deps() {
    local install_dir="$1"
    local scripts_dir="$install_dir/scripts"

    # 任一刷新脚本存在即安装 Playwright
    if [ ! -f "$scripts_dir/refresh-xiaomimimo-cookie.js" ] && [ ! -f "$scripts_dir/refresh-volces-cookie.js" ]; then
        return 0
    fi

    # 检查 node
    if ! command -v node &> /dev/null; then
        print_warning "未检测到 Node.js，cookie 自动刷新功能不可用"
        print_warning "安装 Node.js 后运行: cd $scripts_dir && npm install playwright（刷新脚本复用系统 Chrome，无需下载 chromium）"
        return 0
    fi

    print_info "安装 cookie 刷新依赖 (Playwright)..."

    # 初始化 package.json 并安装 playwright
    cd "$scripts_dir" || return 0
    if [ ! -f "package.json" ]; then
        npm init -y > /dev/null 2>&1
    fi
    npm install playwright 2>&1 | tail -1
    # npx playwright install chromium  # 跳过：cookie 刷新脚本复用系统 Chrome（channel:'chrome'），免下载 chromium 二进制

    cd "$PROJECT_ROOT" || return 0
    print_success "cookie 刷新依赖安装完成"
}

# 配置 Claude Code settings.json
configure_claude() {
    local install_dir="$1"
    local settings_file="$HOME/.claude/settings.json"

    print_info "配置 Claude Code..."

    # 确保 .claude 目录存在
    mkdir -p "$HOME/.claude"

    # 生成 command 路径：默认目录用 ~/.claude 以兼容多端，自定义目录保留完整路径
    if [ "$install_dir" = "$HOME/.claude/statusline" ]; then
        statusline_cmd="bash ~/.claude/statusline/statusline.sh"
    else
        statusline_cmd="bash $install_dir/statusline.sh"
    fi

    print_statusLine_sample() {
        cat << EOF

{
  "statusLine": {
    "command": "$statusline_cmd",
    "type": "command",
    "refreshInterval": 60
  }
}

EOF
    }

    # 读取现有配置或创建新配置
    if [ -f "$settings_file" ]; then
        # 检查是否已有 statusLine 配置
        if grep -q '"statusLine"' "$settings_file" 2>/dev/null; then
            print_warning "settings.json 中已有 statusLine 配置，请手动确认是否需要更新:"
            print_statusLine_sample
        else
            # 没有 statusLine 时自动添加
            if command -v python3 &> /dev/null; then
                cp "$settings_file" "${settings_file}.backup.$(date +%Y%m%d_%H%M%S)"
                python3 << PYEOF
import json
import os

settings_file = os.path.expanduser("~/.claude/settings.json")
install_dir = "$install_dir"

try:
    with open(settings_file, 'r', encoding='utf-8') as f:
        config = json.load(f)
except Exception as e:
    print(f"读取配置失败: {e}")
    config = {}

install_cmd = "$statusline_cmd"
config['statusLine'] = {
    "command": install_cmd,
    "type": "command",
    "refreshInterval": 60
}

with open(settings_file, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print("配置已更新")
PYEOF
                print_success "settings.json 配置完成"
            else
                print_warning "未检测到 Python3，请手动编辑 $settings_file 添加以下配置:"
                print_statusLine_sample
            fi
        fi
    else
        # 创建新配置文件
        cat > "$settings_file" << EOF
{
  "statusLine": {
    "command": "bash $install_dir/statusline.sh",
    "type": "command",
    "refreshInterval": 60
  }
}
EOF
        print_success "创建新配置文件: $settings_file"
    fi
}

# 验证安装
verify_installation() {
    local install_dir="$1"

    print_info "验证安装..."

    # 检查关键文件
    if [ ! -f "$install_dir/statusline.sh" ]; then
        print_error "主脚本未找到"
        return 1
    fi

    if [ ! -f "$install_dir/layout.sh" ]; then
        print_error "布局模块未找到（lib/layout.sh 未复制到位）"
        return 1
    fi

    if [ ! -f "$install_dir/config.json" ]; then
        print_error "配置文件未找到"
        return 1
    fi

    # 测试脚本执行
    test_input='{"cwd":"/home/user/test","display_name":"Claude Sonnet 4.6","used_percentage":30}'
    if ! echo "$test_input" | bash "$install_dir/statusline.sh" > /dev/null 2>&1; then
        print_warning "脚本测试执行失败，可能需要检查依赖"
    else
        print_success "脚本测试通过"
    fi

    print_success "验证完成"
}

# 卸载
uninstall() {
    local install_dir="${1:-$DEFAULT_INSTALL_DIR}"
    local settings_file="$HOME/.claude/settings.json"

    print_info "开始卸载..."

    # 删除安装目录
    if [ -d "$install_dir" ]; then
        rm -rf "$install_dir"
        print_success "已删除: $install_dir"
    fi

    # 从 settings.json 中移除配置
    if [ -f "$settings_file" ]; then
        if command -v python3 &> /dev/null; then
            python3 << PYEOF
import json

settings_file = "$settings_file"

try:
    with open(settings_file, 'r', encoding='utf-8') as f:
        config = json.load(f)

    if 'statusLine' in config:
        del config['statusLine']
        with open(settings_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        print("已从 settings.json 移除 statusline 配置")
except Exception as e:
    print(f"处理 settings.json 时出错: {e}")
PYEOF
        else
            print_warning "请手动从 $settings_file 中移除 statusLine 配置"
        fi
    fi

    print_success "卸载完成"
    print_info "请在 Claude Code 中运行 /reload-plugins 以生效"
}

# 检查安装状态
check_status() {
    local install_dir="${1:-$DEFAULT_INSTALL_DIR}"
    local settings_file="$HOME/.claude/settings.json"

    print_info "检查安装状态..."

    echo ""
    echo "安装目录: $install_dir"
    if [ -d "$install_dir" ]; then
        echo -e "  状态: ${GREEN}已安装${NC}"
        echo "  文件列表:"
        ls -la "$install_dir" | tail -n +2 | awk '{print "    " $9 " (" $5 " bytes)"}'
    else
        echo -e "  状态: ${RED}未安装${NC}"
    fi

    echo ""
    echo "Claude Code 配置: $settings_file"
    if [ -f "$settings_file" ]; then
        if grep -q '"statusLine"' "$settings_file" 2>/dev/null; then
            echo -e "  状态: ${GREEN}已配置${NC}"
            grep -A2 '"statusLine"' "$settings_file" | head -3
        else
            echo -e "  状态: ${YELLOW}未配置${NC}"
        fi
    else
        echo -e "  状态: ${RED}配置文件不存在${NC}"
    fi

    echo ""
    echo "环境变量:"
    if [ -n "$CLAUDE_STATUSLINE_DIR" ]; then
        echo -e "  CLAUDE_STATUSLINE_DIR: ${GREEN}$CLAUDE_STATUSLINE_DIR${NC}"
    else
        echo -e "  CLAUDE_STATUSLINE_DIR: ${YELLOW}未设置 (使用默认值)${NC}"
    fi
}

# 主函数
main() {
    local install_dir="$DEFAULT_INSTALL_DIR"
    local action="install"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dir)
                install_dir="$2"
                shift 2
                ;;
            -u|--uninstall)
                action="uninstall"
                shift
                ;;
            -c|--check)
                action="check"
                shift
                ;;
            *)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 执行操作
    case $action in
        install)
            echo "========================================"
            echo "  Claude Code Statusline 安装程序"
            echo "========================================"
            echo ""

            check_dependencies
            create_install_dir "$install_dir"
            copy_files "$install_dir"
            install_cookie_refresh_deps "$install_dir"
            configure_claude "$install_dir"
            verify_installation "$install_dir"

            echo ""
            echo "========================================"
            print_success "安装完成！"
            echo "========================================"
            echo ""
            echo "安装目录: $install_dir"
            echo ""
            echo "下一步:"
            echo "  1. 在 Claude Code 中运行: /reload-plugins"
            echo "  2. 查看状态栏是否正常显示"
            echo ""
            echo "自定义配置:"
            echo "  编辑 $install_dir/config.json"
            echo ""

            pause
            ;;
        uninstall)
            uninstall "$install_dir"
            pause
            ;;
        check)
            check_status "$install_dir"
            pause
            ;;
    esac
}

# 运行主函数
main "$@"
exit_code=$?

# 如果出错，暂停显示错误信息
if [ $exit_code -ne 0 ]; then
    echo ""
    print_error "脚本执行出错 (退出码: $exit_code)"
    pause
fi

exit $exit_code
