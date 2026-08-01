# 更新日志

本项目所有值得注意的变更均记录在此文件。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本语义遵循 [Semantic Versioning](https://semver.org/)。

## [Unreleased]

## [0.7.0] - 2026-08-01

### Added

- **statusline**: 显示当前会话思考级别（`panel.show_effort`，读取输入 JSON 的 `effort.level`，支持 low/medium/high/xhigh/max 分级着色，模型不支持时自动隐藏）
- **statusline**: 百分比数字支持 7 段数码管样式（`panel.digit_style: segment`，默认开启；可切换回 `subscript` 下标样式）
- **fonts**: 项目自带 Cascadia Code NF 字体（OFL 许可，含 U+1FBF0-U+1FBF9 数码管字形与 Nerd 图标），`bin/install.sh -f` 一键安装（Windows/macOS/Linux 自动适配）
- 社区规范：CODE_OF_CONDUCT.md、SECURITY.md、CONTRIBUTING.md
- CI 配置：GitHub Actions（shellcheck + ubuntu/macos 矩阵测试）
- Issue 模板（Bug 报告 / 功能建议）和 PR 模板
- .editorconfig、.env.example 配置模板
- 基于 git log 生成 CHANGELOG.md

### Changed

- **install**: 安装末尾交互询问是否安装数码管字体（非交互环境自动跳过）；修复 Git Bash 下 `reg` 命令参数被 MSYS 路径转换的问题
- 增强 .gitignore（密钥/缓存/系统文件忽略规则）
- 开启远程仓库 Wiki 功能
- 启用 master 分支保护（需 PR + 1 人审查）

### Other

- 将仓库引用从 `ASmallMatch` 迁移至 `ember-hearted`

## [0.6.0] - 2026-07-22

### Added

- 开源准备：社区规范、CI 配置、模板与文档补充（12 个文件，+665 行）

## [0.5.0] - 2026-07-13

### Fixed

- **statusline**: 修复 macOS bash 3.2 下 `printf %(...)T` 失败导致状态栏无输出的问题
- **install**: 使用 Python `expanduser` 解析家目录，hook command 改用 `~`，确保跨平台路径正确

### Changed

- **install**: 跳过 Chromium 下载，复用系统 Chrome，减少安装体积

### Performance

- **statusline**: 同步路径优化至约 290ms
  - 余额查询改为异步后台刷新（stale-while-revalidate）
  - 消除多余 fork 调用
  - 内建 transcript 解析替代外部子进程

## [0.4.0] - 2026-07-11

### Added

- **install**: install.sh 支持 `-c`（检查状态）和 `-u`（卸载）选项
- **install**: cookie 刷新脚本复用系统 Chrome，免除下载 Playwright Chromium 的步骤

### Changed

- **statusline**: 将项目记忆文档 CLAUDE.md 纳入版本控制

### Performance

- **statusline**: 使用 `node` 批量解析配置，消除重复 fork 子进程的启动延迟
  - mtime 缓存命中时零 fork，miss 时一次 node 调用（约 60ms）
  - 替代此前每次配置读取都需要 Python/grep/sed 子进程的方式

### Other

- 忽略 `.idea/` IDE 配置目录

## [0.3.0] - 2026-06-26

### Added

- **feat**: 火山方舟（Ark）Coding Plan 和 Agent Plan 用量查询支持
- **feat**: 火山方舟 cookie 自动刷新脚本（基于 Playwright）
- **feat**: 火山方舟 Coding/Agent Plan 缓存隔离，Cookie 过期自动检查
- **feat**: SCNet 余额查询支持（API/TokenPlan 双模式自动路由）
- **feat**: Xiaomi MiMo 余额查询支持（含 Token Plan 用量查询 provider）
- **feat**: `resolve_value` 支持逗号分隔多 token 及 `settings.json` env 子对象查找
- **feat**: 添加 Claude Code hooks 配置

### Fixed

- **install**: 重新安装时保留 `cache` 目录，避免丢失 Cookie

### Other

- 忽略 `.firecrawl` 缓存目录

## [0.2.0] - 2026-05-19

### Added

- **feat**: 添加 Kimi Coding Plan 用量查询
- **feat**: 多 provider 架构重构，支持可扩展的余额查询 provider 模式
- **docs**: 更新 README 分隔符说明（↯ / ▸）

## [0.1.0] - 2026-05-11

### Added

- **feat**: 添加 DeepSeek 余额查询功能
- **feat**: 余额查询抽象为可配置的 provider 模式，便于扩展新平台
- **feat**: `api_url` 支持通过配置文件自定义
- **feat**: 余额低于 5 时显示红色，提供直观的低余额告警
- **docs**: 更新 README 使用说明

## [0.0.1] - 2026-03-29

### Added

- Claude Code Statusline 初始版本
- 基础状态栏显示：用户名、目录、模型名、进度条、Git 分支、时间
- 动态颜色进度条（绿色/黄色/红色）
- Git 状态集成（分支名、文件变动统计）
- transcript 解析器用于工具活动和代理状态显示
- 安装脚本 `bin/install.sh`

### Fixed

- 修复 `transcript-parser-lite.js` 语法错误
- 修复 `statusline.sh` 中的两个问题（空分支名处理和特殊字符显示）

---

本项目各版本的提交历史可查阅 `git log`。

[Unreleased]: https://github.com/ember-hearted/statusline/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/ember-hearted/statusline/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/ember-hearted/statusline/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ember-hearted/statusline/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ember-hearted/statusline/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ember-hearted/statusline/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ember-hearted/statusline/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ember-hearted/statusline/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/ember-hearted/statusline/releases/tag/v0.0.1
