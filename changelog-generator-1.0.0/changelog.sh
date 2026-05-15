#!/usr/bin/env bash
#==============================================================================
# changelog.sh — 从 git 历史生成结构化 CHANGELOG.md
# 依赖：仅 bash + git，无其他外部依赖
#==============================================================================

set -eo pipefail
# 允许未定义变量访问（bash 5.0+），用间接引用前先判断存在
set +u
IFS=

#------------------------------------------------------------------------------
# 配置
#------------------------------------------------------------------------------
OUTPUT_FILE="CHANGELOG.md"
INCLUDE_UNRELEASED="false"
MODE="since-tag"
SINCE_DATE=""
FROM_TAG=""
TO_TAG="HEAD"

# 类型 → CHANGELOG 区段映射
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
    ["revert"]="Changed"
)

SKIP_PREFIXES="wip|merge|Merge|Auto-merge|draft|WIP"

#------------------------------------------------------------------------------
# 帮助
#------------------------------------------------------------------------------
usage() {
    cat <<EOF
CHANGELOG 生成器

用法:
    bash changelog.sh [选项]

选项:
    --all                  生成完整历史（所有提交）
    --since=DATE           自指定日期以来的提交（YYYY-MM-DD）
    --from=TAG             从指定 tag 开始
    --to=TAG               到指定 tag 为止（默认 HEAD）
    --unreleased           包含 [Unreleased] 区段
    --output=FILE          指定输出文件（默认 CHANGELOG.md）
    --help, -h             显示本帮助
EOF
    exit 0
}

#------------------------------------------------------------------------------
# 工具函数
#------------------------------------------------------------------------------
log_info()    { echo "[INFO] $*" >&2; }
log_warn()    { echo "[WARN] $*" >&2; }
log_error()   { echo "[ERROR] $*" >&2; }
log_success() { echo "[ OK ] $*"; }

check_git() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log_error "当前目录不是 Git 仓库"
        exit 1
    fi
}

get_latest_tag() {
    git tag -l --sort=-v:refname 2>/dev/null | head -1
}

get_current_version() {
    local tag
    tag=$(get_latest_tag)
    [[ -z "$tag" ]] && echo "Unreleased" || echo "$tag"
}

get_tag_date() {
    git log -1 --format='%ai' "${1:?}" 2>/dev/null | cut -d' ' -f1
}

should_skip() {
    local msg="$1"
    [[ "$msg" =~ ^(wip|merge|Merge|Auto-merge|draft|WIP) ]] && return 0
    return 1
}

# 解析 commit message，返回：TYPE|SCOPE|DESC|ISSUE
# 使用 bash 参数展开，避免正则兼容性
parse_commit() {
    local msg="$1"
    local ctype="" cscope="" cdesc="" issue=""

    # 查找第一个 : 分隔符（bash 原生，无 expr）
    local colon_pos=0
    local i
    for ((i=1; i<=${#msg}; i++)); do
        if [[ "${msg:i-1:1}" == ":" ]]; then
            colon_pos=$i
            break
        fi
    done

    if [[ $colon_pos -gt 1 ]]; then
        local header="${msg:0:$((colon_pos-1))}"
        cdesc="${msg:$colon_pos}"

        # 去掉开头的 :
        cdesc="${cdesc#:}"
        cdesc="${cdesc#"${cdesc%%[![:space:]]*}"}"

        # 从 header 提取 type(scope)，用 bash 原生方式
        local lparen_pos=0 rparen_pos=0
        local j
        for ((j=0; j<${#header}; j++)); do
            if [[ "${header:j:1}" == "(" ]]; then lparen_pos=$((j+1)); fi
            if [[ "${header:j:1}" == ")" ]] && [[ $rparen_pos -eq 0 ]]; then rparen_pos=$j; fi
        done

        if [[ $lparen_pos -gt 0 && $rparen_pos -gt 0 && $rparen_pos -gt $lparen_pos ]]; then
            ctype="${header:0:$((lparen_pos-1))}"
            ctype="${ctype#"${ctype%%[![:space:]]*}"}"
            cscope="${header:lparen_pos:$((rparen_pos-lparen_pos))}"
        else
            ctype="$header"
            ctype="${ctype#"${ctype%%[![:space:]]*}"}"
        fi
    else
        cdesc="$msg"
    fi

    # 提取 Closes/Fixes #N
    if [[ "$cdesc" =~ [Cc]loses?[[:space:]]+# ]] || \
       [[ "$cdesc" =~ [Ff]ixes?[[:space:]]+# ]] || \
       [[ "$cdesc" =~ [Rr]esolves?[[:space:]]+# ]]; then
        local tmp="${cdesc##*#}"
        tmp="${tmp%%[^0-9]*}"
        [[ -n "$tmp" ]] && issue="#${tmp}"
        # 去掉 issue 引用部分
        cdesc="${cdesc%[Cc]loses*#*}"
        cdesc="${cdesc%[Ff]ixes*#*}"
        cdesc="${cdesc%[Rr]esolves*#*}"
        cdesc="${cdesc%"${cdesc##* }"}"
    fi

    # 清理空白
    ctype="${ctype#"${ctype%%[![:space:]]*}"}"
    ctype="${ctype%"${ctype##*[![:space:]]}"}"
    cdesc="${cdesc#"${cdesc%%[![:space:]]*}"}"
    cdesc="${cdesc%"${cdesc##*[![:space:]]}"}"
    cscope="${cscope#"${cscope%%[![:space:]]*}"}"
    cscope="${cscope%"${cscope##*[![:space:]]}"}"

    echo "${ctype}|${cscope}|${cdesc}|${issue}"
}

get_git_range() {
    local range_arg=""
    case "$MODE" in
        since-tag)
            local tag
            tag=$(get_latest_tag)
            if [[ -z "$tag" ]]; then
                if [[ "$INCLUDE_UNRELEASED" == "true" ]]; then
                    log_warn "未找到 git tag，切换为 --all 模式"
                    range_arg="--all"
                else
                    log_error "未找到任何 git tag，请先创建 tag 或使用 --all"
                    exit 1
                fi
            else
                log_info "自 tag '${tag}' 生成 changelog"
                range_arg="${tag}..HEAD"
            fi
            ;;
        all)
            log_info "生成全量历史 changelog"
            range_arg="--all"
            ;;
        since-date)
            log_info "自 ${SINCE_DATE} 生成 changelog"
            range_arg="${SINCE_DATE}..HEAD"
            ;;
        from-tag)
            log_info "从 ${FROM_TAG} 到 ${TO_TAG} 生成 changelog"
            range_arg="${FROM_TAG}..${TO_TAG}"
            ;;
    esac
    echo "$range_arg"
}

#------------------------------------------------------------------------------
# 主流程
#------------------------------------------------------------------------------
main() {
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all) MODE="all" ;;
            --since=*) MODE="since-date"; SINCE_DATE="${1#*=}" ;;
            --from=*) MODE="from-tag"; FROM_TAG="${1#*=}" ;;
            --to=*) TO_TAG="${1#*=}" ;;
            --unreleased) INCLUDE_UNRELEASED="true" ;;
            --output=*) OUTPUT_FILE="${1#*=}" ;;
            --help|-h) usage ;;
            *) log_error "未知参数: $1"; usage ;;
        esac
        shift
    done

    check_git

    local range
    range=$(get_git_range)

    # 初始化 sections
    declare -A sections=(
        ["Added"]=""
        ["Fixed"]=""
        ["Changed"]=""
        ["Removed"]=""
    )
    local breaking_changes=""
    local commit_count=0

    # git log 输出到临时文件（兼容 shallow clone）
    local gitlog_file
    gitlog_file=$(mktemp)
    trap "rm -f '$gitlog_file'" EXIT

    git log $range --pretty=format:"%s||%H||%an" > "$gitlog_file" 2>/dev/null

    local subject hash author
    while IFS='|' read -r subject hash author; do
        [[ -z "$subject" ]] && continue
        should_skip "$subject" && continue

        local parsed
        parsed=$(parse_commit "$subject")
        IFS='|' read -r ctype cscope cdesc issue <<< "$parsed"

        [[ -z "$ctype" && -z "$cdesc" ]] && continue

        local section="Changed"
        [[ -n "$ctype" && -n "${TYPE_MAP[$ctype]}" ]] && section="${TYPE_MAP[$ctype]}"

        # Breaking change 检测
        if [[ "$subject" == *"BREAKING CHANGE"* ]] || [[ "$subject" == *"!" ]]; then
            [[ -n "$breaking_changes" ]] && breaking_changes+=$'\n'
            breaking_changes+="- \`${ctype}${cscope:+(${cscope})}: ${cdesc}\` (${hash:0:7})"
        fi

        # 构建条目
        local scope_tag=""
        [[ -n "$cscope" ]] && scope_tag="(${cscope})"
        local issue_tag=""
        [[ -n "$issue" ]] && issue_tag=" (${issue})"
        local entry="- \`${ctype}${scope_tag}\`: ${cdesc}${issue_tag}"

        if [[ -n "${sections[$section]}" ]]; then
            sections[$section]+=$'\n'"$entry"
        else
            sections[$section]="$entry"
        fi

        ((commit_count++)) 2>/dev/null || true
    done < "$gitlog_file"

    log_info "共处理 $commit_count 条提交"

    # 生成 CHANGELOG.md
    {
        echo "# Changelog"
        echo ""
        echo "All notable changes to this project will be documented in this file."
        echo ""

        local current_version version_date
        current_version=$(get_current_version)
        version_date=$(date '+%Y-%m-%d')

        if [[ "$current_version" == "Unreleased" ]]; then
            echo "## [Unreleased]"
        else
            echo "## [${current_version}] - ${version_date}"
        fi
        echo ""

        for section in Added Fixed Changed Removed; do
            if [[ -n "${sections[$section]}" ]]; then
                echo "### ${section}"
                echo -e "${sections[$section]}"
                echo ""
            fi
        done

        if [[ -n "$breaking_changes" ]]; then
            echo "### Breaking Changes"
            echo -e "$breaking_changes"
            echo ""
        fi
    } > "${OUTPUT_FILE}.tmp"

    mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
    log_success "完成！文件已写入: ${OUTPUT_FILE}"
}

main "$@"
