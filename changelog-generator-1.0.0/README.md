# CHANGELOG Generator

从 git 历史自动生成结构化 CHANGELOG.md。

## 安装（3步）

### 第1步：下载脚本
```bash
curl -fsSL https://raw.githubusercontent.com/Ikalus1988/claude-builders-bounty/changelog-generator-skILL/changelog-generator-1.0.0/changelog.sh -o changelog.sh
chmod +x changelog.sh
```

### 第2步：放入项目
```bash
mv changelog.sh /your/project/path/
cd /your/project/path/
```

### 第3步：生成 CHANGELOG
```bash
# 自上次 tag 至今（推荐）
./changelog.sh

# 或生成完整历史
./changelog.sh --all
```

---

## 高级用法

```bash
# 指定日期范围
./changelog.sh --since=2024-01-01

# 指定版本区间
./changelog.sh --from=v1.0.0 --to=v2.0.0

# 指定输出文件
./changelog.sh --output= HISTORY.md

# 包含未发布内容
./changelog.sh --unreleased
```

## 与 Claude Code 配合

将 SKILL.md 放入 Claude Code skills 目录，即可用：
```
/generate-changelog
```

## 依赖

仅需 `bash` + `git`，无其他外部依赖。

## 示例输出

见 [SAMPLE-CHANGELOG.md](./SAMPLE-CHANGELOG.md)
