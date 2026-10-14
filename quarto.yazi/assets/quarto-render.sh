#!/bin/bash
# ============================================================
# quarto-render.sh — Yazi quarto 插件配套脚本 (v0.7.6)
#
# 基于 quarto + quarto-gbt9704 扩展，无 PrettyDoc 依赖：
#
#   .md / .qmd → quarto render → gbt9704-pdf + gbt9704-docx + gbt9704-html + PNG
#
# 工作流：
#   1. 确保 ~/.yazi-quarto/ 存在并已安装 quarto-gbt9704 扩展
#   2. 复制输入文件到 ~/.yazi-quarto/
#   3. quarto render --to gbt9704-pdf + gbt9704-docx + gbt9704-html
#   4. 浏览器截图 HTML → PNG
#   5. 复制输出回原始目录，清理临时文件
#
# Usage: quarto-render.sh <file_path> [gbt9704|textbook]
# ============================================================
set -euo pipefail

# ─── 颜色 ───
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── 路径 ───
WORK_DIR="$HOME/.yazi-quarto"
# @dist = CI 物化的自包含分支（浮动指向最新发布，装过即跳过不自动升级）
# 手动更新: cd "$HOME/.yazi-quarto" && quarto update "songwupei/quarto-gbt9704@dist" --no-prompt
EXT_NAME="songwupei/quarto-gbt9704@dist"

# 扩展最低版本：低于此版本会在渲染前自动更新。
# 0.8.1 起：PDF 默认引擎 XeLaTeX（LuaLaTeX 在部分机器无法嵌入系统 CJK 字体）、
# 标题/页码/版心按 GB/T 9704 修正、新增 fandol 选项、基类由 memoir 迁移到 ctexart。
REQUIRED_EXT_VERSION="0.8.1"

# ─── 超时保护 ───
# quarto / LaTeX 出错时可能停在交互提示上等输入（实测挂过 12 分钟以上），
# 因此所有外部命令都套一层 timeout；超时退出码 124 单独提示。
# 可用 QUARTO_RENDER_TIMEOUT / QUARTO_ADD_TIMEOUT 覆盖（秒）。
TIMEOUT_BIN=$(command -v timeout || true)
RENDER_TIMEOUT="${QUARTO_RENDER_TIMEOUT:-600}"
ADD_TIMEOUT="${QUARTO_ADD_TIMEOUT:-300}"

_run_t() {  # _run_t <超时秒数> <命令...>
    local t="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" "$t" "$@"
    else
        "$@"
    fi
}

# ─── 版本比较: $1 >= $2 ───
_ver_ge() {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$2" ]
}

# ─── 定位已安装的 gbt9704 扩展目录 ───
# 兼容两种布局：quarto add 安装的 songwupei/gbt9704，以及手动投放的 gbt9704
_gbt_ext_dir() {
    local d
    for d in "$WORK_DIR/_extensions/songwupei/gbt9704" "$WORK_DIR/_extensions/gbt9704"; do
        if [ -f "$d/_extension.yml" ]; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    return 1
}

# ─── 确保扩展版本不低于要求，必要时自动更新 ───
_ensure_ext_version() {
    local ext_dir ext_yml
    if ! ext_dir=$(_gbt_ext_dir); then
        echo -e "${RED}❌ 未找到 gbt9704 扩展（$WORK_DIR/_extensions 下）${NC}" >&2
        exit 1
    fi
    ext_yml="$ext_dir/_extension.yml"
    local installed
    installed=$(grep -oP 'version:\s*\K[0-9.]+' "$ext_yml" 2>/dev/null | head -n 1 || true)
    [ -n "$installed" ] || installed="0"
    if _ver_ge "$installed" "$REQUIRED_EXT_VERSION"; then
        echo "✅ quarto-gbt9704 v${installed}（≥ v${REQUIRED_EXT_VERSION}）"
        return 0
    fi
    echo "🔄 quarto-gbt9704 v${installed} < v${REQUIRED_EXT_VERSION}，尝试自动更新 ..."
    if _run_t "$ADD_TIMEOUT" quarto update "$EXT_NAME" --no-prompt >/dev/null 2>&1; then
        installed=$(grep -oP 'version:\s*\K[0-9.]+' "$ext_yml" 2>/dev/null | head -n 1 || true)
        [ -n "$installed" ] || installed="0"
        if _ver_ge "$installed" "$REQUIRED_EXT_VERSION"; then
            echo "✅ 扩展已更新至 v${installed}"
            return 0
        fi
    fi
    echo -e "${RED}❌ quarto-gbt9704 v${installed} 低于要求 v${REQUIRED_EXT_VERSION}，且自动更新失败${NC}" >&2
    echo "   请手动运行:" >&2
    echo "   cd $WORK_DIR && quarto update $EXT_NAME --no-prompt" >&2
    exit 1
}

# ─── 参数检查 ───
if [ $# -lt 1 ]; then
    echo -e "${RED}❌ 用法: $0 <file_path> [gbt9704|textbook]${NC}" >&2
    exit 1
fi

INPUT_FILE="$1"
FORCE_FORMAT="${2:-}"   # 显式指定格式，跳过自动检测

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}❌ 文件不存在: $INPUT_FILE${NC}" >&2
    exit 1
fi

# 统一成绝对路径：脚本中途会 cd "$WORK_DIR"，相对路径到那时就找不到了
INPUT_FILE=$(realpath "$INPUT_FILE")

INPUT_FILENAME=$(basename "$INPUT_FILE")
INPUT_BASENAME="${INPUT_FILENAME%.*}"
INPUT_EXT="${INPUT_FILENAME##*.}"
ORIG_DIR=$(realpath "$(dirname "$INPUT_FILE")")

echo "📄 输入文件: $INPUT_FILENAME  (.${INPUT_EXT})"
echo "📁 原始目录: $ORIG_DIR"

# ─── 检查 quarto ───
if ! command -v quarto &>/dev/null; then
    echo -e "${RED}❌ 未安装 quarto${NC}" >&2
    echo "   安装方法: https://quarto.org/docs/get-started/" >&2
    exit 1
fi
echo "✅ quarto: $(quarto --version 2>/dev/null || echo 'ok')"

# ─── 初始化工作目录 ───
_init_workdir() {
    # 创建目录
    if ! mkdir -p "$WORK_DIR" 2>/dev/null; then
        echo -e "${RED}❌ 无法创建 $WORK_DIR（权限不足？）${NC}" >&2
        exit 1
    fi

    # 安装/更新 quarto-gbt9704 扩展
    echo "🔧 检查 quarto-gbt9704 扩展 ..."
    cd "$WORK_DIR"

    if ! _gbt_ext_dir >/dev/null; then
        echo "📦 安装 $EXT_NAME ..."
        if ! _run_t "$ADD_TIMEOUT" quarto add "$EXT_NAME" --no-prompt 2>&1; then
            echo -e "${RED}❌ 扩展安装失败: $EXT_NAME${NC}" >&2
            echo "   请检查网络连接，或手动运行:" >&2
            echo "   cd $WORK_DIR && quarto add $EXT_NAME" >&2
            exit 1
        fi
        echo "✅ 扩展已安装"
    else
        echo "✅ 扩展已就绪"
    fi

    # Install textbook extension (independent repo)
    if [ ! -d "_extensions/songwupei/textbook" ] && [ ! -d "_extensions/textbook" ]; then
        echo "📦 安装 textbook 扩展 ..."
        if ! _run_t "$ADD_TIMEOUT" quarto add songwupei/quarto-textbook --no-prompt 2>&1; then
            echo -e "${YELLOW}⚠  textbook 扩展安装失败（不影响 gbt9704 渲染）${NC}"
        else
            echo "✅ textbook 扩展已安装"
        fi
    fi

    # ─── 同步布局: gbt9704-layout.json → .lua / .def ───
    _sync_layout() {
        local gbt_dir=""
        # 找到 gbt9704 扩展目录
        for d in "_extensions/songwupei/gbt9704" "_extensions/gbt9704"; do
            if [ -f "$d/_extension.yml" ]; then gbt_dir="$d"; break; fi
        done
        if [ -z "$gbt_dir" ]; then return; fi

        local gen="${gbt_dir}/assets/scripts/json2def.py"
        if [ ! -f "$gen" ]; then return; fi

        local json="${gbt_dir}/gbt9704-layout.json"
        local lua="${gbt_dir}/gbt9704-layout.lua"
        local def="${gbt_dir}/gbt9704-layout.def"

        # 仅在 JSON 比 .lua 新时才重新生成
        if [ "$json" -nt "$lua" ]; then
            echo "🔄 同步布局: gbt9704-layout.json → .lua / .def ..."
            python3 "$gen" "$json" --lua > "$lua" 2>&1 || true
            python3 "$gen" "$json" > "$def" 2>&1 || true
            echo "✅ 布局已同步"
        fi
    }
    _sync_layout
}

# ─── 清理 ───
_cleanup() {
    rm -f "$WORK_DIR/$INPUT_FILENAME" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}"_files/* 2>/dev/null || true
    rmdir "$WORK_DIR/${INPUT_BASENAME}"_files 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.pdf" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.docx" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.html" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.png" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.qmd" 2>/dev/null || true
    rm -f "$WORK_DIR/${INPUT_BASENAME}.tex" 2>/dev/null || true
    rm -f "$WORK_DIR/gbt9704.cls" 2>/dev/null || true
    rm -f "$WORK_DIR/zhlineskip.sty" 2>/dev/null || true
    rm -rf "$WORK_DIR/images" 2>/dev/null || true
}

# ─── 浏览器检测 ───
_detect_browser() {
    if command -v google-chrome-stable &>/dev/null; then
        echo "google-chrome-stable"
    elif command -v chromium &>/dev/null; then
        echo "chromium"
    else
        echo ""
    fi
}

_init_workdir
_ensure_ext_version

# ─── 复制输入文件 + include 目标到工作目录 ───
cp "$INPUT_FILE" "$WORK_DIR/$INPUT_FILENAME"
echo "📋 已复制 → $WORK_DIR/$INPUT_FILENAME"

# 复制 {{< include ... >}} 引用的文件
for inc in $(sed -n 's/.*{{<\s*include\s\+\([^>]*\)\s*>.*/\1/p' "$INPUT_FILE" 2>/dev/null); do
    inc=$(echo "$inc" | xargs)
    if [ -n "$inc" ] && [ -f "$ORIG_DIR/$inc" ]; then
        cp "$ORIG_DIR/$inc" "$WORK_DIR/$inc"
        echo "📋 include → $WORK_DIR/$inc"
    fi
done

# 复制 images/ 目录（如果存在）
if [ -d "$ORIG_DIR/images" ]; then
    cp -r "$ORIG_DIR/images" "$WORK_DIR/images" 2>/dev/null
    echo "📋 images/ → $WORK_DIR/images/"
fi

cd "$WORK_DIR"

# ─── normalize blank lines: table rows compact, everything else spaced ───
_normalize_blank_lines() {
    local file="$1"
    python3 -c "
import sys
with open('$file', 'r') as f:
    lines = f.readlines()

result = []
in_yaml = False
yaml_done = False

def is_table(s):
    return s.startswith('|') and s.endswith('|')

for i, line in enumerate(lines):
    stripped = line.rstrip('\n')
    prev_s = lines[i-1].rstrip('\n') if i > 0 else ''
    next_s = lines[i+1].rstrip('\n') if i+1 < len(lines) else ''

    if stripped == '---' and not yaml_done:
        in_yaml = not in_yaml
        if not in_yaml: yaml_done = True
        result.append(line)
        continue
    if in_yaml:
        result.append(line)
        continue

    # remove blank lines between table rows
    if not stripped:
        if (is_table(prev_s) and is_table(next_s)) or \
           (is_table(prev_s) and next_s == '|---|---|---|') or \
           (prev_s == '|---|---|---|' and is_table(next_s)):
            continue

    result.append(line)

    # add blank between non-table consecutive non-blank lines
    if stripped and next_s:
        if is_table(stripped) and is_table(next_s): continue
        if stripped == '|---|---|---|' or next_s == '|---|---|---|': continue
        if lines[i+1].strip():
            result.append('\n')

with open('$file', 'w') as f:
    f.writelines(result)
"
}

_normalize_blank_lines "$INPUT_FILENAME"
echo "📋 空行已规整"

# ─── 格式检测：从 YAML frontmatter 读取 format 字段 ───
_detect_format() {
    local file="$1"
    local fmt=""
    if [ -f "$file" ]; then
        # 提取 YAML frontmatter 中的 format: 字段值
        fmt=$(sed -n '/^---$/,/^---$/p' "$file" | grep -E '^\s*format:\s*' | head -1 | sed 's/.*format:\s*//' | xargs)
    fi
    # 默认 gbt9704-pdf；如果指定了 textbook-pdf 则使用 textbook-pdf
    if [ "$fmt" = "textbook-pdf" ]; then
        echo "textbook"
    else
        echo "gbt9704"
    fi
}

# ─── PDF-only 检测：textbook 格式仅支持 PDF ───
_is_pdf_only() {
    local fmt="$1"
    [ "$fmt" = "textbook" ]
}

# ─── 格式确定：显式参数 > YAML frontmatter 自动检测 ───
FORMAT=""
if [ -n "$FORCE_FORMAT" ]; then
    FORMAT="$FORCE_FORMAT"
    echo "🎯 指定格式: ${FORMAT}-pdf"
else
    FORMAT=$(_detect_format "$INPUT_FILE")
    echo "🎯 检测到格式: ${FORMAT}-pdf"
fi
PDF_ONLY=$(_is_pdf_only "$FORMAT" && echo true || echo false)
if $PDF_ONLY; then
    echo "ℹ️  ${FORMAT} 格式仅支持 PDF 输出"
fi

# ─── pandoc filter-only: 生成 .gbt9704.md 中间文件 ───
# (仅 gbt9704 格式；textbook 格式跳过)
if ! $PDF_ONLY; then
FILTER_DIR="$WORK_DIR/_extensions/songwupei/gbt9704/assets/filters"
echo ""
echo "📋 生成 .gbt9704.md（filter 处理后的中间 markdown）..."
if _run_t 120 pandoc "$INPUT_FILENAME" \
    --lua-filter="$FILTER_DIR/gbt9704-metadata.lua" \
    --lua-filter="$FILTER_DIR/numbering-to-headings.lua" \
    --lua-filter="$FILTER_DIR/heading-demotion.lua" \
    --lua-filter="$FILTER_DIR/title-promotion.lua" \
    --lua-filter="$FILTER_DIR/format-zhidu.lua" \
    --lua-filter="$FILTER_DIR/table-colwidths.lua" \
    --lua-filter="$FILTER_DIR/format-legal.lua" \
    --lua-filter="$FILTER_DIR/fcolumn.lua" \
    --lua-filter="$FILTER_DIR/gbt9704-emoji.lua" \
    -t gfm -o "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" 2>&1; then
    echo "   ✓ .gbt9704.md 完成"
else
    echo -e "  ${YELLOW}⚠  .gbt9704.md 生成失败（不影响后续渲染）${NC}"
fi
fi  # if ! $PDF_ONLY

# ─── quarto render ───
echo ""
echo "🖨️  quarto render --to ${FORMAT}-pdf ..."
set +e
_run_t "$RENDER_TIMEOUT" quarto render "$INPUT_FILENAME" --to ${FORMAT}-pdf 2>&1
RENDER_RC=$?
set -e
if [ $RENDER_RC -ne 0 ]; then
    if [ $RENDER_RC -eq 124 ]; then
        echo -e "${RED}❌ PDF 渲染超时（${RENDER_TIMEOUT}s，可用 QUARTO_RENDER_TIMEOUT 调整）${NC}" >&2
    else
        echo -e "${RED}❌ PDF 渲染失败（exit=${RENDER_RC}）${NC}" >&2
    fi
    if [ -f "$WORK_DIR/${INPUT_BASENAME}.log" ]; then
        echo "── LaTeX 日志末尾 (${INPUT_BASENAME}.log) ──" >&2
        tail -n 25 "$WORK_DIR/${INPUT_BASENAME}.log" >&2 2>/dev/null || true
    fi
    _cleanup
    exit 1
fi
echo "   ✓ PDF 完成"

if ! $PDF_ONLY; then
echo "🖨️  quarto render --to ${FORMAT}-docx ..."
set +e
_run_t "$RENDER_TIMEOUT" quarto render "$INPUT_FILENAME" --to ${FORMAT}-docx 2>&1
RENDER_RC=$?
set -e
if [ $RENDER_RC -ne 0 ]; then
    if [ $RENDER_RC -eq 124 ]; then
        echo -e "${RED}❌ DOCX 渲染超时（${RENDER_TIMEOUT}s）${NC}" >&2
    else
        echo -e "${RED}❌ DOCX 渲染失败（exit=${RENDER_RC}）${NC}" >&2
    fi
    _cleanup
    exit 1
fi
echo "   ✓ DOCX 完成"

echo "🖨️  quarto render --to ${FORMAT}-html ..."
if _run_t "$RENDER_TIMEOUT" quarto render "$INPUT_FILENAME" --to ${FORMAT}-html 2>&1; then
    echo "   ✓ HTML 完成"

    # ─── HTML → PNG 截图 ───
    BROWSER=$(_detect_browser)
    if [ -n "$BROWSER" ] && [ -f "$WORK_DIR/${INPUT_BASENAME}.html" ]; then
        echo "📸 $BROWSER 截图 → PNG ..."
        PNG_WIDTH=900
        if _run_t 180 "$BROWSER" \
            --headless --disable-gpu --no-sandbox \
            --screenshot="$WORK_DIR/${INPUT_BASENAME}.png" \
            --window-size="${PNG_WIDTH},24000" \
            --default-background-color=ffffff \
            --hide-scrollbars \
            --virtual-time-budget=10000 \
            "file://${WORK_DIR}/${INPUT_BASENAME}.html" 2>/dev/null; then

            # ─── 裁白边 + 加边距（如果 ImageMagick 可用）───
            PNG_FILE="$WORK_DIR/${INPUT_BASENAME}.png"
            if [ -f "$PNG_FILE" ]; then
                MAGICK_CMD=""
                command -v magick &>/dev/null && MAGICK_CMD="magick" || {
                    command -v convert &>/dev/null && MAGICK_CMD="convert"
                }
                if [ -n "$MAGICK_CMD" ]; then
                    "$MAGICK_CMD" "$PNG_FILE" -trim +repage -bordercolor white -border 20x20 "$PNG_FILE" 2>/dev/null || true
                fi
                echo "   ✓ PNG 完成 ($(du -h "$PNG_FILE" | cut -f1))"
            fi
        else
            echo -e "  ${YELLOW}⚠  PNG 截图失败（HTML 保留）${NC}"
        fi
    elif [ -z "$BROWSER" ]; then
        echo -e "  ${YELLOW}⚠  未检测到浏览器（chrome/chromium），跳过 PNG 截图${NC}"
        echo "   💡 安装: sudo pacman -S google-chrome  或  sudo pacman -S chromium"
    fi
else
    echo -e "${YELLOW}⚠  HTML 渲染失败（可能需要 quarto-gbt9704 ≥ v0.3.1）${NC}"
fi
fi  # if ! $PDF_ONLY

# ─── 复制输出回原目录 ───
COPIED=""
COPY_FMT=""
if [ -f "$WORK_DIR/${INPUT_BASENAME}.pdf" ]; then
    cp "$WORK_DIR/${INPUT_BASENAME}.pdf" "$ORIG_DIR/"
    COPIED="${COPIED}pdf "
    COPY_FMT="${COPY_FMT}PDF "
fi
if [ -f "$WORK_DIR/${INPUT_BASENAME}.docx" ]; then
    cp "$WORK_DIR/${INPUT_BASENAME}.docx" "$ORIG_DIR/"
    COPIED="${COPIED}docx "
    COPY_FMT="${COPY_FMT}DOCX "
fi
if [ -f "$WORK_DIR/${INPUT_BASENAME}.html" ]; then
    cp "$WORK_DIR/${INPUT_BASENAME}.html" "$ORIG_DIR/"
    COPIED="${COPIED}html "
    COPY_FMT="${COPY_FMT}HTML "
fi
if [ -f "$WORK_DIR/${INPUT_BASENAME}.png" ]; then
    cp "$WORK_DIR/${INPUT_BASENAME}.png" "$ORIG_DIR/"
    COPIED="${COPIED}png "
    COPY_FMT="${COPY_FMT}PNG "
fi
if [ -f "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" ]; then
    cp "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" "$ORIG_DIR/"
    COPIED="${COPIED}md "
    COPY_FMT="${COPY_FMT}MD "
fi

# ─── 保存清理版源文件 (方案 C: 清理版 .gbt9704.qmd) ───
# 复制源文件到目标目录，命名为 .gbt9704.qmd（不含 filter 处理，仅格式清理）
GB9704_QMD="${INPUT_BASENAME}.gbt9704.qmd"
if [ -f "$ORIG_DIR/$INPUT_FILENAME" ]; then
    cp "$ORIG_DIR/$INPUT_FILENAME" "$ORIG_DIR/$GB9704_QMD"
    COPIED="${COPIED}qmd "
    COPY_FMT="${COPY_FMT}QMD "
fi

if [ -z "$COPIED" ]; then
    echo -e "${YELLOW}⚠️  警告: 没有找到输出文件${NC}"
    _cleanup
    exit 1
fi

echo "📤 ${COPY_FMT}→ ${ORIG_DIR}"

# ─── 清理 ───
_cleanup
echo "🧹 已清理临时文件"
echo "✅ 完成!"
