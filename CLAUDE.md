# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个跨平台的 Claude Code 状态栏脚本，支持动态颜色进度条、多平台 API 用量显示和 Git 状态集成。

## 常用命令

### 安装与配置

```bash
# 安装到默认目录 (~/.claude/statusline)
bash bin/install.sh

# 安装到自定义目录
bash bin/install.sh -d /path/to/custom/dir

# 检查安装状态
bash bin/install.sh -c

# 卸载
bash bin/install.sh -u
```

### 测试脚本

```bash
# 本地测试状态栏脚本
echo '{"cwd":"/home/user/test","display_name":"Claude Sonnet 4.6","used_percentage":30}' | bash bin/statusline.sh
```

### 安装后生效

在 Claude Code 中运行：
```
/reload-plugins
```

## 代码架构

### 文件结构

```
├── bin/
│   ├── install.sh         # 安装脚本：部署到 ~/.claude/statusline/
│   ├── query-balance.sh   # 余额查询调度器：推断 provider、解析凭据、后台刷新
│   └── statusline.sh      # 主脚本：解析输入、生成状态栏输出
├── lib/
│   ├── layout.sh          # 布局模块：统一开发/安装双布局的资源定位（find_file/find_dir）
│   └── json.sh            # JSON 读取模块：json_get（awk 实现，node/jq 不可用时兜底）
├── config/
│   ├── config.json        # 配置文件：颜色阈值、显示选项、balance provider 列表
│   └── providers/         # 余额查询 provider 适配器（每 provider 一个脚本）
├── scripts/
│   └── refresh-*-cookie.*         # Cookie 自动刷新（Playwright 复用系统 Chrome）
├── docs/
│   ├── CLAUDE.md          # 项目记忆文档
│   ├── README.md          # 使用文档
│   └── cookie-contract.md # Cookie 契约：谁写、谁读、何时刷新
├── CONTEXT.md             # 领域词汇表（Layout/Provider/统一缓存等）
└── CLAUDE.md              # 根目录文档入口
```

### 核心逻辑

**bin/statusline.sh** 接收 JSON 输入（来自 Claude Code），格式为：
```json
{
  "cwd": "/current/working/directory",
  "display_name": "Claude Sonnet 4.6",
  "used_percentage": 30
}
```

输出格式（最多三行，后两行无内容时省略）：

```
第一行: 进度条+百分比 · 余额 · 思考级别 · Git分支状态 · PR徽章 · 时间
第二行: 当前目录（↯ 指示符）
第三行: Tasks 进度
```

### 配置系统

配置文件位于 `config/config.json`，采用分组结构：

**colors 分组** - 颜色相关配置：
- `colors.thresholds.green`: 绿色阈值（默认 55%）
- `colors.thresholds.yellow`: 黄色阈值（默认 75%）
- `colors.branch`: 分支名颜色代码（默认 "33" 橙色）

**panel 分组** - 面板显示选项：
- `panel.git.show_git`: 是否显示 Git 状态（默认 true）
- `panel.git.show_git_changes`: 是否显示文件变动统计（默认 true）
- `panel.show_time`: 是否显示时间（默认 true）
- `panel.show_tasks`: 是否显示 TaskCreate 任务进度（默认 true，读 `~/.claude/tasks/session-<id前8位>/`，会话无任务时自动隐藏）
- `panel.show_pr`: 是否显示当前分支开放 PR 徽章（默认 true，从输入 JSON 的 `pr.number`/`pr.review_state` 读取，带 OSC 8 可点击链接，无 PR 时自动隐藏）
- `panel.show_effort`: 是否显示思考级别（默认 true，从输入 JSON 的 `effort.level` 读取，模型不支持时自动隐藏）

配置解析优先用一次 `node` 调用批量提取所有字段（约 60ms，避免反复 fork 子进程）；`node` 不可用时 fallback 到 `parse_config`（grep/sed 管道，在 Windows Git Bash 上约 1 秒/次）。支持嵌套路径如 `colors.thresholds.green`。

### 安装流程

1. 复制文件到 `~/.claude/statusline/`
2. 修改 `~/.claude/settings.json` 添加 statusLine 配置
3. 配置格式：
   ```json
   {
     "statusLine": {
       "command": "bash ~/.claude/statusline/statusline.sh",
       "type": "command",
       "refreshInterval": 60
     }
   }
   ```

`refreshInterval`（秒）让 Claude Code 在事件触发之外定时重跑脚本——空闲时（无新消息）状态栏默认不刷新，时间/余额等外部数据会冻结；脚本本身有 mtime 配置缓存与余额 TTL 节流，定时重跑成本接近零。

## 颜色逻辑

进度条颜色根据 `used_percentage` 变化：
- < green 阈值（55%）：绿色
- green ~ yellow 阈值（55%~75%）：黄色
- > yellow 阈值（75%）：红色

## 布局与路径引用（lib/layout.sh 统一管理）

项目在两种布局下运行：开发布局（`bin/` `scripts/` `config/` `lib/` 分目录）与安装布局（文件拍平到 `~/.claude/statusline/`，`providers/` `scripts/` 保留子目录）。资源定位统一由 `lib/layout.sh` 负责：

- 脚本顶部 source 布局模块（dev：`../lib/layout.sh`；安装：同目录 `layout.sh`），然后可用 `LAYOUT_ROOT`/`CONFIG_DIR`/`CACHE_DIR`
- `find_file <name>` / `find_dir <name>`：按根 → bin/ → scripts/ → lib/ → config/ 顺序查找，兼容两种布局
- `load_module <name>`：加载 lib/ 下的共享模块（如 json.sh）
- `install.sh` 的 `PROJECT_ROOT` 由 `LAYOUT_ROOT` 导出（目录同源），复制清单仍需显式维护——新增共享文件时要同步：
  1. 放入 `lib/`（或按布局放置）
  2. `install.sh` 的 `copy_files` 增加对应 `cp`
  3. `find_file` 的搜索前缀覆盖不到新目录时，在 `_layout_prefixes` 中追加

**已安装用户升级**：重跑 `bash bin/install.sh` 即可（已有备份→清空→重装机制），新文件 `layout.sh`/`json.sh` 会复制到位。

**Cookie provider 注意事项**：cookie 文件（`cache/<provider>_cookie.txt`）由刷新脚本写入、provider 消费、check 脚本检查过期，契约见 `docs/cookie-contract.md`。

## Windows Git Bash 兼容性

### grep -c 行为差异
Windows Git Bash 中 `grep -c` 会输出文件名，需要 `head -1` 提取第一个数字：
```bash
count=$(echo "$text" | grep -c "pattern" 2>/dev/null | head -1 || echo "0")
```

### 路径处理
- 使用 Bash 工具时优先使用相对路径（如 `bin/statusline.sh`）
- 或使用转换后的 Unix 路径格式（`/e/dev-tools/` 而不是 `E:\dev-tools\`）
- 避免在 Read 工具中使用 Windows 绝对路径（常出现 "File does not exist" 错误）

## 余额查询（stale-while-revalidate）

余额显示采用 stale-while-revalidate，同步路径零等待：

- **同步路径**：直接 `read` 统一缓存文件 `cache/balance_current.txt`（零 fork、零等待）
- **后台刷新**：节流标记 `cache/balance_refresh.marker` 记录上次刷新时间，TTL（300s）外才 `&` 后台 spawn `query-balance.sh`，其 stdout 原子写入（tmp + mv）统一缓存
- **节流**：TTL 内不重复 spawn 调度器，避免高频刷新堆积进程；调度器内部另有 provider 层 5min TTL 控制是否真发网络请求
- **降级**：缓存文件不存在时余额片段为空，主状态行照常输出

注：统一缓存 `balance_current.txt` 由后台调度器写入，而非直接读 provider 各自的缓存（如 `balance_deepseek.txt`）--因同步路径不知当前 provider（推断逻辑在调度器内）。

## 配置解析

### 解析策略（性能关键路径）

配置解析是状态栏启动耗时的关键路径。曾因 `parse_config` 在 Windows Git Bash 上每次调用约 1 秒（fork 子进程开销大）、被调用 10 次累计 ~8.6 秒，导致状态栏启动慢。当前策略：

- **mtime 缓存命中**（常态）：`config.json` 未比缓存新时，`source` 预解析的 `cache/config_parsed.sh`（零 fork）
- **miss**：一次 `node` 调用批量提取全部字段（约 60ms），`eval` 注入并写入缓存
- **fallback**：`node` 不可用时走 `lib/json.sh` 的 `json_get`（awk 实现，慢但功能可用）

### 嵌套 JSON 路径

两条路径都支持点号分隔的嵌套路径，如 `colors.thresholds.green`。主路径在 node 内用 `reduce` 逐级取值；fallback 路径用 `json_get`：

```bash
green_threshold=$(json_get "$CONFIG_FILE" "colors.thresholds.green" "55")
```

`json_get` 也供 `query-balance.sh` 的 settings.json 兜底使用（grep/sed 版 parse_config 已移除，其嵌套花括号匹配不支持嵌套对象，是历史遗留缺陷）。

### 配置分组结构

config.json 采用分组结构：
- `colors` - 颜色相关（thresholds, branch）
- `panel` - 显示选项（git 子组, show_time, show_tasks 等）
