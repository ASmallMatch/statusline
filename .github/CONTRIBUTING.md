# 贡献指南

## 项目简介

Statusline 是一个跨平台的 Claude Code 状态栏（bash 脚本），支持动态颜色进度条、多平台 API 用量显示和 Git 状态集成。它通过解析 Claude Code 提供的 JSON 输入，生成高信息密度的终端状态栏输出。

## 技术栈

- **核心语言**：纯 Bash（需兼容 macOS bash 3.2、Windows Git Bash、Linux bash）
- **辅助工具**：Node.js（用于 cookie 刷新脚本和 transcript 解析）
- **配置格式**：JSON（`config/config.json`）

## 开发环境搭建

1. 克隆仓库：

   ```bash
   git clone https://github.com/ember-hearted/statusline.git
   cd statusline
   ```

2. 本地安装测试：

   ```bash
   bash bin/install.sh
   ```

   或者安装到自定义目录：

   ```bash
   bash bin/install.sh -d /path/to/custom/dir
   ```

3. 检查安装状态：

   ```bash
   bash bin/install.sh -c
   ```

4. 在 Claude Code 中生效：

   ```
   /reload-plugins
   ```

## 代码规范

### 通用原则

- **跨平台兼容性**：脚本必须在 macOS bash 3.2（Apple 默认版本）、Windows Git Bash 和主流 Linux 发行版上运行
- **文件大小限制**：单个脚本不超过 800 行，保持高内聚低耦合
- **配置驱动**：所有行为参数从 `config/config.json` 读取，避免在脚本中硬编码阈值或颜色值

### macOS bash 3.2 兼容要点

macOS 默认的 bash 3.2 缺少许多 bash 4+ 特性，编写时需注意：

- **关联数组**：bash 4.0+ 特性，在 macOS 上不可用，请使用普通数组或 `case`/`eval` 替代
- **`**` 操作符**：bash 4.0+ 特性，在 macOS 上不可用，请使用 `${var,,}` 的 `tr` 或 `sed` 替代（但 `${var^^}` 的 `tr` 也可以在 3.2 用）
- **`printf %(datefmt)T`**：在 bash 4.2+ 中可用，macOS bash 3.2 不支持，需改用 `date` 命令获取时间格式化
- **`declare -g`**：bash 4.2+ 特性，在 macOS 上不可用
- **`read -t` 超时**：macOS 上的行为可能略有不同
- **`set -e` 陷阱**：bash 3.2 中，命令替换内部的 `set -e` 行为与 bash 4+ 不同，复杂表达式中的失败路径可能导致脚本提前退出

### Git 工作流

1. **Fork 仓库**：点击 GitHub 上的 Fork 按钮创建自己的副本
2. **创建分支**：从 master 分支创建功能分支或修复分支

   ```bash
   git checkout -b feature/your-feature-name
   # 或
   git checkout -b fix/your-fix-name
   ```

3. **提交变更**：提交信息格式为中文描述，末尾加上签名行

   ```
   feat(scope): 简明的中文描述

   详细说明（可选）
   一只小火柴๑҉
   ```

4. **创建 Pull Request**：将分支推送到远程后，创建 PR 至上游仓库的 `master` 分支
5. **等待审查**：维护者会审查您的代码，可能会有需要修改的地方

## 测试方式

### 状态栏脚本测试

通过 `echo` 管道传递 JSON 输入来测试 `statusline.sh`：

```bash
echo '{"cwd":"/home/user/test","display_name":"Claude Sonnet 4.6","used_percentage":30}' | bash bin/statusline.sh
```

测试不同 `used_percentage` 值验证颜色阈值逻辑（绿色 < 55%，黄色 55%-75%，红色 > 75%）。

### 安装脚本测试

```bash
# 测试安装流程
bash bin/install.sh

# 测试自定义目录安装
bash bin/install.sh -d /tmp/test-statusline

# 测试检查状态
bash bin/install.sh -c

# 测试卸载
bash bin/install.sh -u
```

### 跨平台测试

由于 macOS 默认的 bash 3.2 缺少多项 bash 4+ 特性，建议在以下环境中进行测试：

- macOS（系统默认 bash 3.2）
- Linux 发行版（bash 4+）
- Windows Git Bash

## 配置说明

配置文件位于 `config/config.json`，采用分组结构：

```json
{
  "colors": {
    "thresholds": {
      "green": 55,
      "yellow": 75
    },
    "branch": "33"
  },
  "panel": {
    "git": {
      "show_git": true,
      "show_git_changes": true
    },
    "show_time": true,
    "show_tasks": true,
    "show_pr": true
  }
}
```

配置支持嵌套路径访问，如 `colors.thresholds.green`。添加新配置项时请保持此结构一致性。

## 行为准则

本仓库采用 [Contributor Covenant](/CODE_OF_CONDUCT.md) 作为行为准则。所有贡献者都需遵守，以维护一个开放、友善的社区环境。

## 问题反馈

使用 GitHub Issues 报告 bug 或提出功能建议：

- 报告 bug 时请说明运行环境（macOS/Linux/Windows Git Bash）和复现步骤
- 功能建议请说明使用场景和期望行为
