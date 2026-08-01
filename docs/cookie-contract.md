# Cookie 契约

Provider 的余额/用量查询中，Cookie 认证型 provider（scnet、scnet-tp、volces、xiaomimimo）依赖浏览器登录态。本文档记录 Cookie 的**谁写、谁读、何时刷新**，是三方之间的唯一契约参考。

## 契约总览

```
┌─────────────────────────────────────────────────────────────┐
│  cache/ 目录（~/.claude/statusline/cache/）                  │
│                                                             │
│  scnet_cookie.txt        ← 手动/脚本写入，scnet.sh 读取      │
│  scnet_tp_cookie.txt     ← 手动/脚本写入，scnet-tp.sh 读取   │
│  volces_cookie.txt       ← refresh-volces-cookie.sh 写入     │
│  │                          volces.sh 读取                  │
│  │                          check-volces-cookie.sh 检查过期  │
│  xiaomimimo_cookie.txt   ← refresh-xiaomimimo-cookie.sh 写入│
│                             xiaomimimo.sh 读取              │
└─────────────────────────────────────────────────────────────┘
```

**命名约定**：`cache/<provider>_cookie.txt`。路径目前由各脚本各自推导
（`${HOME}/.claude/statusline/cache/`），未跟随 `CLAUDE_STATUSLINE_DIR` 环境变量。

## 各方职责

### 写入方（刷新脚本）

| 脚本 | 写入文件 | 触发方式 | 依赖 |
|---|---|---|---|
| `scripts/refresh-volces-cookie.sh` | `volces_cookie.txt` | 手动 / `check-volces-cookie.sh` / SessionStart hook | Playwright（channel: chrome，复用系统 Chrome，不下载 chromium） |
| `scripts/refresh-xiaomimimo-cookie.sh` | `xiaomimimo_cookie.txt` | 手动 | Playwright（同上） |

- 两个刷新脚本均支持 `--quiet` 静默模式（无输出，供 hook/后台调用）。
- 核心逻辑在 `refresh-*.js`（Node.js + Playwright），`.sh` 是入口封装。
- Playwright 依赖在安装时由 `install.sh` 的 `install_cookie_refresh_deps` 安装
  （`cd $install_dir/scripts && npm install playwright`）。

### 检查方（过期检测）

`scripts/check-volces-cookie.sh`：

- 检查 `volces_cookie.txt` 是否存在、是否过期（Cookie 中 `userInfo` 相关字段）。
- 过期时调用 `refresh-volces-cookie.sh --quiet` 自动刷新。
- 由 `install.sh` 配置为 `settings.json` 的 SessionStart hook
  （`matcher: "startup"`，`async: true`），每次 Claude Code 会话启动时触发。
- 无 Python3 环境时 install.sh 打印手动配置示例。

### 消费方（Provider）

| Provider | 读取文件 | 认证细节 |
|---|---|---|
| `scnet.sh` | `scnet_cookie.txt` | Cookie 认证（登录 scnet.cn 后获取） |
| `scnet-tp.sh` | `scnet_tp_cookie.txt` | Cookie 认证（同上，TokenPlan 资源） |
| `volces.sh` | `volces_cookie.txt` | Cookie + `x-csrf-token`（从 Cookie 中提取 `csrfToken=` 值，需含 userInfo/digest/csrfToken） |
| `xiaomimimo.sh` | `xiaomimimo_cookie.txt` | Cookie（`api-platform_serviceToken`），优先取 `$1` 参数，其次文件 |

### 手动获取（无自动化刷新时）

scnet / scnet-tp / volces 均支持手动方式：浏览器登录 → F12 复制 Cookie → 存入
对应的 `cache/<provider>_cookie.txt`。具体步骤见各 provider 脚本头部注释。

## 修改约定

- **新增 Cookie 认证型 provider**：遵循 `cache/<provider>_cookie.txt` 命名约定，
  在 provider 脚本头部注释写明 Cookie 来源与获取方式。
- **路径变更**：需同步修改消费 provider、刷新脚本、检查脚本三处（当前分散定义，
  本契约文档是唯一交叉参考）。
- 若需要随 `CLAUDE_STATUSLINE_DIR` 自定义安装目录，Cookie 路径需统一改为
  从布局模块（`lib/layout.sh` 的 `CACHE_DIR`）推导。
