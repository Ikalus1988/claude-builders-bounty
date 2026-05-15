---
name: changelog-generator
description: >
  从 git 历史自动生成结构化 CHANGELOG.md。支持 Conventional Commits 标准分类，
  输出 Added / Fixed / Changed / Removed 分段格式。通过 SKILL 命令或 bash 脚本两种方式调用。
  触发场景：需要生成 CHANGELOG、更新版本记录、管理项目发布-notes 时使用。
---

# CHANGELOG 生成器

自动从 git 历史生成符合 [Keep a Changelog](https://keepachangelog.com/) 规范的 `CHANGELOG.md`。

## 工作方式

### 方式一：作为 Claude Code SKILL 使用

在当前 Git 仓库目录下直接调用：

```
/generate-changelog [选项]
```

**常用示例：**

```
/generate-changelog                      # 自上次 git tag 至今的所有提交
/generate-changelog --all               # 完整历史生成（所有提交）
/generate-changelog --since="2024-01-01" # 指定日期之后
/generate-changelog --from v1.0.0       # 从指定 tag 开始
/generate-changelog --output CHANGELOG.md  # 指定输出文件
/generate-changelog --unreleased        # 包含 Unreleased 区段
```

### 方式二：作为独立 bash 脚本使用

在任意 Git 仓库中运行：

```bash
bash changelog.sh [选项]
```

**Docker 化使用（无需本地安装）：**

```bash
docker run --rm -v "$(pwd)":/repo ghcr.io/claude-builders-bounty/changelog-generator:latest
```

## 核心功能

### 自动分类

将每条 git commit 按 Conventional Commits 标准分类到对应区段：

| GitHub 提交类型 | CHANGELOG 输出区段 |
|----------------|-------------------|
| `feat`         | **Added**         |
| `fix`          | **Fixed**         |
| `perf`, `refactor`, `ci`, `chore` | **Changed** |
| `docs`         | **Changed**（文档变更）|
| `test`, `style` | **Changed**（辅助变更）|
| `deprecate`, `remove` | **Removed** |
| 跳过（wip, merge, revert 等） | 不输出 |

### 智能解析规则

- **scope 提取**：从 `feat(用户模块): 添加手机登录` 解析出 scope
- **多行 commit**：只取第一行作为 subject
- **Breaking Changes**：自动在底部追加 Breaking Changes 列表
- **关联 Issue**：提取 `Closes #N` / `Fixes #N` 等，追加到对应条目

### 输出格式

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- `feat(scope)`: 简短描述 (#issue)

### Fixed
- `fix(scope)`: 简短描述

## [1.2.0] - 2024-06-01

### Added
- `feat(auth)`: 支持 GitHub OAuth 登录

### Changed
- `refactor(api)`: 重构用户接口返回结构
```

## 技术实现

### 依赖

脚本仅依赖 Git 环境，无需额外安装任何工具（bash + git）。

### 关键 Git 命令

```bash
# 获取上次 tag 之后的提交
git log $(git describe --tags --abbrev=0)..HEAD --pretty=format:"%s||%H||%an" 2>/dev/null

# 获取所有提交（--all 模式）
git log --pretty=format:"%s||%H||%an" HEAD

# 获取所有 tag
git tag -l --sort=-v:refname | head -5
```

### 类型映射表

```bash
declare -A TYPE_MAP=(
  ["feat"]="Added"
  ["fix"]="Fixed"
  ["perf"]="Changed"
  ["refactor"]="Changed"
  ["docs"]="Changed"
  ["style"]="Changed"
  ["test"]="Changed"
  ["ci"]="Changed"
  ["chore"]="Changed"
  ["deprecate"]="Removed"
  ["remove"]="Removed"
)
```

## 集成到项目

### 1. 克隆脚本到本地

```bash
# 方式一：直接下载
curl -fsSL https://raw.githubusercontent.com/claude-builders-bounty/claude-builders-bounty/main/changelog.sh -o changelog.sh
chmod +x changelog.sh

# 方式二：作为 git 模板脚本
git config --global init.templateDir ~/.git-template
curl -fsSL ... -o ~/.git-template/hooks/changelog.sh
```

### 2. 配置 package.json（可选）

```json
{
  "scripts": {
    "changelog": "bash changelog.sh",
    "changelog:unreleased": "bash changelog.sh --unreleased"
  }
}
```

### 3. 初始化版本 tag

```bash
git tag -a v0.1.0 -m "Initial release"
git push origin --tags
```

## 常见问题

**Q: 分支提交如何过滤？**
A: 默认只处理当前分支。使用 `--all` 可合并所有分支（慎用）。

**Q: 中文 commit message 能否正常处理？**
A: 可以。脚本使用 UTF-8 编码，中文、emoji 均能正确解析。

**Q: 私有仓库是否安全？**
A: 完全本地运行，不访问任何远程 API，不上传任何数据。

**Q: 没有 tag 怎么办？**
A: 报错退出，建议先打第一个 tag，或使用 `--all` 生成全量历史。

## 参考规范

- [Keep a Changelog](https://keepachangelog.com/)
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/)
- [GitHub Changelog Generator](https://github.com/github-changelog-generator/github-changelog-generator)
