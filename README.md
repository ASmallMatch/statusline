# Claude Code Statusline

| 中文
| [English](README_en.md)

跨平台的 Claude Code 状态栏脚本，支持动态颜色进度条、Git 状态集成和实时活动显示。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 功能特性

- **进度条前置**：电池风格进度条显示在第一行开头
- **两级目录显示**：显示 `parent/current` 格式的路径
- **电池风格进度条**：`•` 正极 + `■` 满格 + `□` 空格 + 下标百分比
- **动态颜色**：根据 Context 使用量显示不同颜色
  - 🟢 绿色 (< 55%)
  - 🟡 黄色 (55% ~ 75%)
  - 🔴 红色 (> 75%)
- **LLM 余额查询**：可配置的多 provider 模式，支持 DeepSeek、Kimi、Xiaomi MiMo、SCNet（API/TokenPlan 双模式自动路由）、火山方舟（Coding/Agent Plan 双模式自动路由）等厂商余额/用量显示
- **智能切换**：配置多个 provider，自动显示当前生效（token 有效）的那一个
- **实时活动显示**：显示进行中的 Tools、Agents、Todos 数量
- **Git 状态集成**：显示分支名和文件变动统计
- **跨平台**：Windows (Git Bash/WSL)、macOS、Linux

## 安装

### 方式一：一键安装（推荐）

```bash
# 使用 curl 直接下载安装脚本并执行
curl -fsSL https://raw.githubusercontent.com/ember-hearted/statusline/master/bin/install.sh | bash

# 或在 Claude Code 中直接运行
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ember-hearted/statusline/master/bin/install.sh)"
```

安装完成后，在 Claude Code 中运行：
```
/reload-plugins
```

### 方式二：克隆后安装

```bash
# 克隆仓库
git clone git@github.com:ember-hearted/statusline.git
cd statusline

# 运行安装脚本
bash bin/install.sh
```

安装完成后，在 Claude Code 中运行：
```
/reload-plugins
```

### 安装脚本选项

```bash
# 查看帮助
bash bin/install.sh --help

# 安装到自定义目录
bash bin/install.sh -d /path/to/custom/dir

# 检查安装状态
bash bin/install.sh -c

# 卸载
bash bin/install.sh -u
bash bin/install.sh -f
```

### 重新安装与缓存保留

重新运行 `bash bin/install.sh` 升级时，安装脚本会先备份旧目录再覆盖。`~/.claude/statusline/cache/` 目录（存放火山方舟 Cookie、余额缓存等运行时状态）会在覆盖过程中被保留，无需重新登录或重新配置 Cookie。

### 平台兼容性

无需额外安装 Bash：macOS 自带的 bash 3.2、Windows Git Bash/WSL、Linux 发行版自带 bash 均可直接运行。

### 手动安装

如果安装脚本无法使用，可以手动安装：

```bash
# 1. 克隆仓库
git clone git@github.com:ember-hearted/statusline.git
cd statusline

# 2. 创建安装目录
mkdir -p ~/.claude/statusline

# 3. 复制文件
cp bin/statusline.sh ~/.claude/statusline/
cp bin/query-balance.sh ~/.claude/statusline/
cp config/config.json ~/.claude/statusline/
cp config/providers/*.sh ~/.claude/statusline/providers/
cp scripts/transcript-parser-lite.js ~/.claude/statusline/
mkdir -p ~/.claude/statusline/scripts
cp scripts/refresh-xiaomimimo-cookie.js ~/.claude/statusline/scripts/
cp scripts/refresh-xiaomimimo-cookie.sh ~/.claude/statusline/scripts/

# 4. 添加执行权限
chmod +x ~/.claude/statusline/statusline.sh

# 5. 配置 Claude Code
# 编辑 ~/.claude/settings.json，添加：
# {
#   "statusLine": {
#     "command": "bash ~/.claude/statusline/statusline.sh",
#     "type": "command"
#   }
# }

# 6. 重载插件
# 在 Claude Code 中运行: /reload-plugins
```

## 配置

编辑 `~/.claude/statusline/config.json`：

```json
{
  "bar_length": 10,
  "colors": {
    "thresholds": {
      "green": 55,
      "yellow": 75
    },
    "branch": "33"
  },
  "balance": {
    "deepseek": {
      "token_env": "DEEPSEEK_API_KEY",
      "api_url": "https://api.deepseek.com/user/balance"
    },
    "kimi": {
      "token_env": "ANTHROPIC_API_KEY",
      "api_url": "https://api.kimi.com/coding/v1/usages"
    },
    "xiaomimimo": {
      "api_url": "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage"
    },
    "scnet": {
      "token_env": "ANTHROPIC_AUTH_TOKEN",
      "api_url": "https://www.scnet.cn/acx/charge/flow/llmapi/resource/list"
    },
    "scnet-tp": {
      "token_env": "ANTHROPIC_AUTH_TOKEN",
      "api_url": "https://www.scnet.cn/acx/charge/account/currentuser/tokenplan/list"
    },
    "volces": {
      "token_env": "ANTHROPIC_AUTH_TOKEN",
      "api_url": "https://console.volcengine.com/api/top/ark/cn-beijing/2024-01-01"
    }
  },
  "panel": {
    "git": {
      "show_git": true,
      "show_git_changes": true
    },
    "show_time": true,
    "show_tools": true,
    "show_agents": true,
    "show_todos": true
  }
}
```

`balance` 为**对象格式**，key 是 provider 名称。系统通过读取 `ANTHROPIC_BASE_URL` 自动推断当前使用的 provider，直接命中对应的配置。

### 配置项说明

**colors 分组** - 颜色相关配置：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `colors.thresholds.green` | 绿色阈值（百分比） | 55 |
| `colors.thresholds.yellow` | 黄色阈值（百分比） | 75 |
| `colors.branch` | 分支名颜色代码 | 33（橙色） |

**balance 分组** - 余额/用量查询配置：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `balance.<name>.token_env` | API token 对应的环境变量名 | 见各 provider 说明 |
| `balance.<name>.api_url` | 余额查询 API 地址 | 见各 provider 说明 |

**Token 配置**：在 `~/.claude/settings.json` 的 `env` 中配置：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.kimi.com/coding/",
    "ANTHROPIC_API_KEY": "eyJ...",
    "DEEPSEEK_API_KEY": "sk-..."
  }
}
```

系统会自动读取 `ANTHROPIC_BASE_URL`，从域名中提取 provider 标识（如 `api.kimi.com` → `kimi`），然后直接命中 `balance.kimi` 配置。如果 `ANTHROPIC_BASE_URL` 未设置或匹配失败，则 fallback 到 `balance` 对象的第一个 key。

**panel 分组** - 面板显示选项：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `panel.git.show_git` | 是否显示 Git 状态 | true |
| `panel.git.show_git_changes` | 是否显示文件变动统计 | true |
| `panel.show_time` | 是否显示时间 | true |
| `panel.show_tools` | 是否显示工具活动 | true |
| `panel.show_agents` | 是否显示代理状态 | true |
| `panel.show_todos` | 是否显示待办进度 | true |
| `panel.digit_style` | 百分比数字样式：`segment`（数码管 7 段）或 `subscript`（下标） | `segment` |

| `bar_length` | 进度条长度 | 10 |

### 数码管字体（panel.digit_style: "segment"）

百分比数字默认使用 **7 段数码管字符**（Unicode U+1FBF0–U+1FBF9），显示效果：

```
❦ •■■■□□□□□□🯳🯰 ‹¥102.17› ↯ user/test ▸ no-git ▸ 19:37
```

数码管字符需要终端字体包含对应字形。项目自带 **Cascadia Code NF**（微软官方 Nerd Font 版，OFL 开源许可，`fonts/` 目录），三端通用：

```bash
# 一键安装字体（Windows/macOS/Linux 自动适配）
bash bin/install.sh -f
```

安装后在终端设置中把字体切换为 **Cascadia Code NF** 即可。安装时的交互提示也会询问是否安装。

> 若终端字体不支持（显示为方块/问号），可在 `config.json` 中切回通用下标样式：
> ```json
> { "panel": { "digit_style": "subscript" } }
> ```

## 显示效果

```
# 主状态行（DeepSeek）
❦ •■■■■■□□□□₅₆‹¥98.66› ↯ claude-space/statusline ▸  test ~2 -1 ▸ 05:42

# 主状态行（Kimi）
❦ •■■■■■□□□□₅₆‹Kimi 69%/10%› ↯ claude-space/statusline ▸  test ~2 -1 ▸ 05:42


# 主状态行（Xiaomi MiMo）
❦ •■■■■■□□□□₅₆‹Mimo 74%(30.3亿/41.0亿)› ↯ claude-space/statusline ▸  test ~2 -1 ▸ 05:42

# 主状态行（SCNet）
❦ •■■■■■□□□□₅₆‹SCNet 49%(490万/1000万)› ↯ claude-space/statusline ▸  test ~2 -1 ▸ 05:42

# 有活动时的附加行
  ❦ Tools  3 running
  ❦ Agents 2 running
  ❦ Todos  2/5
```

格式说明：

- `❦` - 进度条前缀符号
- `•` - 电池正极（始终显示）
- `■■■■■` - 已使用的 Context（绿色/黄色/红色）
- `□□□□` - 未使用的 Context
- `₅₆` - 使用百分比（下标数字）
- `‹¥98.66›` - DeepSeek 余额（括号内着色）
- `‹Kimi 69%/10%›` - Kimi Coding Plan 用量（5h使用率/周度使用率，各自着色）
- `‹Mimo 74%(30.3亿/41.0亿)›` - Xiaomi MiMo Token Plan 用量（百分比着色）
- `‹SCNet 49%(490万/1000万)›` - SCNet 资源用量（API 模式，百分比着色，已用/总量）
- `‹SCNet-TP 0%(0/6万)›` - SCNet TokenPlan 用量（CREDITS，百分比着色，已用/总量）
- `‹方舟Coding 21%/3%›` - 火山方舟 Coding Plan 用量（5h/周使用率，各自着色）；Agent Plan 显示为 `方舟Agent`
- `↯` - 余额与路径之间的分隔符
- `▸` - 路径、分支、时间之间的分隔符
- `claude-space/statusline` - 两级目录名（青色）
- ` test` - Git 分支（橙色）
- `~2 -1` - 文件变动统计（修改2个，删除1个）
- `05:42` - 时间（灰色）

**活动行**（仅当有进行中的活动时显示）：
- `❦ Tools  3 running` - 有3个工具正在执行（黄色）
- `❦ Agents 2 running` - 有2个代理正在工作（青色）
- `❦ Todos  2/5` - 2个待办进行中，总共5个（绿色）

## 性能优化

- **Transcript 活动行（stale-while-revalidate）**：Tools/Agents/Todos 统计改为同步读缓存、后台异步刷新，首次渲染不再等待 node 解析（Windows 每次 spawn node 约 70-100ms），首屏延迟明显下降
- **布局自定位零 fork**：安装布局下 `lib/layout.sh` 自定位不再启动子 shell，每次渲染省 ~45ms
- **后台刷新不阻塞渲染**：transcript 与余额的后台刷新子 shell 均重定向 stdout/stderr，避免调用方等待管道 EOF 拖住状态栏

## 文件结构

```
~/.claude/statusline/
├── config.json              # 配置文件
├── statusline.sh            # 主脚本
├── query-balance.sh         # 余额查询调度器
├── providers/               # Provider 脚本目录
│   ├── deepseek.sh          # DeepSeek 余额查询
│   ├── kimi.sh              # Kimi Coding Plan 用量查询
│   ├── xiaomimimo.sh        # Xiaomi MiMo Token Plan 用量查询
│   ├── scnet.sh             # SCNet 资源用量查询（API 模式）
│   ├── scnet-tp.sh          # SCNet TokenPlan 用量查询（开发中）
│   └── volces.sh            # 火山方舟 Coding/Agent Plan 用量查询（Cookie 鉴权）
├── scripts/                 # 辅助脚本目录
│   ├── refresh-xiaomimimo-cookie.js   # MiMo cookie 自动刷新（Playwright）
│   ├── refresh-xiaomimimo-cookie.sh   # MiMo cookie 刷新入口脚本
│   ├── refresh-volces-cookie.js       # 火山方舟 cookie 自动刷新（Playwright）
│   ├── refresh-volces-cookie.sh       # 火山方舟 cookie 刷新入口脚本
│   └── check-volces-cookie.sh         # 火山方舟 cookie 过期检查（SessionStart hook 调用）
├── cache/                   # 运行时缓存（自动生成）
│   ├── xiaomimimo_cookie.txt          # MiMo 认证 cookie
│   ├── volces_cookie.txt              # 火山方舟认证 cookie
│   ├── balance_volces_coding.txt      # 火山方舟 Coding Plan 用量缓存
│   ├── balance_volces_agent.txt       # 火山方舟 Agent Plan 用量缓存
│   └── balance_*.txt                  # 其他 provider 余额缓存
└── transcript-parser-lite.js # Transcript 解析器
```

| 文件 | 说明 |
|------|------|
| `statusline.sh` | 主脚本：解析输入、生成状态栏输出 |
| `config.json` | 配置文件：颜色阈值、显示选项、余额 provider |
| `query-balance.sh` | 余额调度器：读取配置并调用对应 provider（支持 jq 多 provider 解析） |
| `providers/` | Provider 脚本目录，每个 `.sh` 封装一个厂商的查询逻辑，自行管理颜色和格式 |
| `scripts/` | 辅助脚本目录，包含 MiMo cookie 自动刷新等工具 |
| `transcript-parser-lite.js` | Transcript 解析器：提取 Tools/Agents/Todos 状态 |
| `install.sh` | 安装脚本：部署到 `~/.claude/statusline/` |

## Provider 说明

### DeepSeek

- **接口**：`GET https://api.deepseek.com/user/balance`
- **显示**：`¥余额`
- **颜色**：余额 < ¥5 红色，否则黄色

### Kimi Coding Plan

- **接口**：`GET https://api.kimi.com/coding/v1/usages`
- **显示**：`Kimi 5h使用率%/周度使用率%`
- **颜色**：两个百分比**各自独立着色**
  - 5小时窗口：>80% 红，>50% 黄，否则绿
  - 周度配额：>90% 红，>70% 黄，否则绿
- **Token**：使用 `ANTHROPIC_API_KEY`（因为 Kimi 通过 OpenAI 兼容协议接入）

### Xiaomi MiMo Token Plan

- **接口**：`GET https://platform.xiaomimimo.com/api/v1/tokenPlan/usage`
- **认证**：Cookie（`api-platform_serviceToken`），**非 API Key**
- **显示**：`Mimo 百分比(已用/总量)`
- **颜色**：>90% 红，>70% 黄，否则绿
- **依赖**：Node.js + Playwright（安装脚本自动处理，手动安装需运行 `cd ~/.claude/statusline/scripts && npm install playwright && npx playwright install chromium`）
- **Cookie 获取**：小米未提供 API Key 查询用量的接口，需通过浏览器登录获取 cookie
  ```bash
  # 首次运行：打开浏览器手动登录小米账号
  ~/.claude/statusline/scripts/refresh-xiaomimimo-cookie.sh

  # 后续运行：复用登录态自动刷新（无头模式）
  ~/.claude/statusline/scripts/refresh-xiaomimimo-cookie.sh --quiet
  ```
- **Cookie 有效期**：约 1 天，过期后脚本会自动尝试刷新并提示
- **定时刷新建议**：配合 cron 每 12 小时刷新一次
  ```bash
  0 */12 * * * ~/.claude/statusline/scripts/refresh-xiaomimimo-cookie.sh --quiet
  ```
- **config.json 配置**：无需 `token_env`，脚本从 `~/.claude/statusline/cache/xiaomimimo_cookie.txt` 读取
  ```json
  "xiaomimimo": {
    "api_url": "https://platform.xiaomimimo.com/api/v1/tokenPlan/usage"
  }
  ```

### SCNet

SCNet（超算互联网）有两种计费模式，系统根据 API key 格式自动路由：

| 模式 | API Key 格式 | 余额接口 |
|------|-------------|---------|
| API 模式 | `sk-*`（普通） | `POST .../flow/llmapi/resource/list` |
| TokenPlan 模式 | `sk-tp*` | `GET .../tokenplan/list` |

**两种模式的共同点**：
- **认证**：Cookie（浏览器登录 [scnet.cn](https://www.scnet.cn) 后获取），**非 API Key**
- **颜色**：>90% 红，>70% 黄，否则绿
- **Cookie 有效期**：取决于登录会话有效期，过期后脚本会提示重新登录

#### API 模式（`scnet`）
- **显示**：`SCNet 百分比(已用/总量)`
- **接口**：`POST https://www.scnet.cn/acx/charge/flow/llmapi/resource/list`
- **Cookie 文件**：`~/.claude/statusline/cache/scnet_cookie.txt`

#### TokenPlan 模式（`scnet-tp`）
- **显示**：`SCNet-TP 百分比(已用/总量)`
- **接口**：`GET https://www.scnet.cn/acx/charge/account/currentuser/tokenplan/list`
- **Cookie 文件**：`~/.claude/statusline/cache/scnet_tp_cookie.txt`
- **响应格式**：`data[].totalAmount`（总量 CREDITS） / `data[].usedAmount`（已用）

**Cookie 获取**：
```bash
# 1. 浏览器登录 https://www.scnet.cn
# 2. F12 → Network → 复制 Cookie 请求头
# 3. 存入对应模式的 Cookie 文件
echo 'cookie字符串' > ~/.claude/statusline/cache/scnet_cookie.txt     # API 模式
echo 'cookie字符串' > ~/.claude/statusline/cache/scnet_tp_cookie.txt   # TokenPlan 模式
```

**自动路由**：系统从 `ANTHROPIC_BASE_URL` 提取 `scnet`，再读取 `ANTHROPIC_AUTH_TOKEN` 检查 key 格式：
- `sk-tp*` → 路由到 `scnet-tp` provider
- 其他 → 路由到 `scnet` provider

**config.json 配置**：
```json
"scnet": {
    "token_env": "ANTHROPIC_AUTH_TOKEN",
    "api_url": "https://www.scnet.cn/acx/charge/flow/llmapi/resource/list"
},
"scnet-tp": {
    "token_env": "ANTHROPIC_AUTH_TOKEN",
    "api_url": "https://www.scnet.cn/acx/charge/account/currentuser/tokenplan/list"
}
```
- **config.json 配置**：无需 `token_env`，脚本从 `~/.claude/statusline/cache/scnet_cookie.txt` 读取
  ```json
  "scnet": {
    "api_url": "https://www.scnet.cn/acx/charge/flow/llmapi/resource/list"
  }
  ```

### 火山方舟 (Volcengine Ark)

火山方舟的 Coding Plan 与 Agent Plan 套餐用量查询。根据 `ANTHROPIC_BASE_URL` 的路径自动路由：

- `/api/coding` → `GetCodingPlanUsage` 接口，标签 `方舟Coding`
- `/api/plan` → `GetAgentPlanAFPUsage` 接口，标签 `方舟Agent`

显示格式为 `5h使用率/周使用率`，两个百分比各自按阈值着色，例如 `方舟Coding 21%/3%`。

- **认证方式**：Cookie + `x-csrf-token`（火山控制台代理接口，非官方 OpenAPI）。火山官方 OpenAPI 需 AK/SK V4 签名，本插件走控制台 Cookie 代理以避免额外密钥。
- **Cookie 文件**：`~/.claude/statusline/cache/volces_cookie.txt`
- **token_env**：`ANTHROPIC_AUTH_TOKEN`（仅用于通过调度器的 token 非空检查，实际鉴权用 Cookie）

**Cookie 获取**：

1. 浏览器登录 https://console.volcengine.com
2. F12 → Network → 找到任意请求 → 复制完整 `Cookie` 头（需含 `userInfo`、`digest`、`csrfToken` 字段）
3. 存入文件：
   ```bash
   echo 'cookie字符串' > ~/.claude/statusline/cache/volces_cookie.txt
   chmod 600 ~/.claude/statusline/cache/volces_cookie.txt
   ```

> ⚠️ Cookie 中 `digest` JWT 有效期约 2 天，过期后状态栏会显示 `方舟 ⚠ Cookie已过期` 提示，需重新复制。

**自动刷新**（推荐）：提供 Playwright 脚本自动登录并提取 Cookie，免去手动复制：

```bash
~/.claude/statusline/scripts/refresh-volces-cookie.sh          # 首次运行会打开浏览器登录
~/.claude/statusline/scripts/refresh-volces-cookie.sh --quiet  # 静默模式（登录态失效时发飞书通知并退出，适合 cron）
```

- 首次运行打开浏览器手动登录火山引擎账号，登录态持久化到 `cache/volces_state/`
- 后续运行无头自动刷新，写入 `volces_cookie.txt`
- 依赖 Node.js + Playwright（安装时自动安装，与 MiMo 刷新脚本共用）
- 建议配合 cron 或 `/loop` 每 1–2 天刷新一次
- `--quiet` 模式登录态失效时通过 lark-cli 发飞书私信提醒（同一天去重，不刷屏），需手动跑 `--force` 重新登录

**config.json 配置**：
```json
"volces": {
  "token_env": "ANTHROPIC_AUTH_TOKEN",
  "api_url": "https://console.volcengine.com/api/top/ark/cn-beijing/2024-01-01"
}
```

## 许可证

MIT License

---

作者：一只小火柴๑҉ <lin.llt@qq.com>
