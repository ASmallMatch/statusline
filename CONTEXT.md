# Statusline Context

Claude Code 状态栏项目：读取 harness 的 JSON 输入（cwd、模型、用量百分比、transcript 路径），输出彩色状态行；按 provider 查询 API 余额/用量并显示。

## Language

**Layout**：
项目文件在两种布局下运行：开发布局（`bin/`、`scripts/`、`config/`、`lib/` 分目录）与安装布局（`install.sh` 复制到 `~/.claude/statusline/`，多数文件拍平到根，`providers/` 与 `scripts/` 保留子目录）。脚本必须能在两种布局下定位资源，查找逻辑收敛在 `lib/layout.sh`。
_Avoid_: 路径结构、目录结构

**Provider**：
余额/用量查询适配器，位于 `config/providers/`（或安装目录 `providers/`）。接口约定：`$1` = API token、`$2` = api_url（可选）、stdout 输出带 ANSI 颜色的字符串、退出码 0 = 成功。认证方式各异：Bearer token（deepseek）、Cookie（scnet/volces/xiaomimimo）、Cookie + csrf（volces）。
_Avoid_: 查询脚本、余额脚本

**Provider 推断**：
从 `ANTHROPIC_BASE_URL` 域名推导当前 provider key 的启发式（剥 TLD/子域 + balance 对象查 key），失败时 fallback 到 balance 对象的第一个 key。scnet-tp 是特例（sk-tp token 前缀检测）。
_Avoid_: 路由、匹配

**统一缓存**：
stale-while-revalidate 机制：同步路径直接 `read` 统一缓存文件（`cache/balance_current.txt`）零等待；后台由 `query-balance.sh` 调度器刷新（节流 marker + provider 层 5min TTL）。统一缓存与 provider 各自的缓存（`cache/balance_<provider>.txt`）分离。
_Avoid_: 余额缓存

**Cookie 刷新**：
`scripts/refresh-*-cookie.sh/.js` 通过 Playwright（channel: chrome，复用系统 Chrome）维护 provider 登录态，写入 `cache/` 目录；`check-volces-cookie.sh` 在 SessionStart hook 中检查过期并触发刷新。Cookie 契约细节见 docs/README.md。
_Avoid_: 登录、认证维护
