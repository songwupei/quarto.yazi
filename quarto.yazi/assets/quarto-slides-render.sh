#!/bin/bash
# ============================================================
# quarto-slides-render.sh — Yazi quarto 幻灯片脚本 (v0.7.0)
#
#   .md / .qmd → quarto render → gbt9704-pptx + gbt9704-beamer
#
# 依赖 gbt9704 扩展 ≥ v0.7.0（pptx/beamer 已合并入 gbt9704）
#
# Usage: quarto-slides-render.sh <file_path> <pptx|beamer>
#   pptx   → 同时渲染 PPTX + Beamer PDF
#   beamer → 仅渲染 Beamer PDF
# ============================================================
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ $# -lt 2 ]; then
    echo -e "${RED}❌ 用法: $0 <file_path> <pptx|beamer>${NC}" >&2
    exit 1
fi

INPUT_FILE="$1"
FORMAT="$2"

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}❌ 文件不存在: $INPUT_FILE${NC}" >&2
    exit 1
fi

case "$FORMAT" in
    pptx|beamer) ;;
    *) echo -e "${RED}❌ 不支持的格式: $FORMAT${NC}" >&2; exit 1 ;;
esac

INPUT_FILENAME=$(basename "$INPUT_FILE")
INPUT_BASENAME="${INPUT_FILENAME%.*}"
BEAMER_NAME="${INPUT_BASENAME}-beamer"
ORIG_DIR=$(realpath "$(dirname "$INPUT_FILE")")

echo "📄 输入文件: $INPUT_FILENAME"

# ─── paths ───
WORK_DIR="$HOME/.yazi-quarto"
EXT_NAME="songwupei/quarto-gbt9704"

# Check quarto
if ! command -v quarto &>/dev/null; then
    echo -e "${RED}❌ 未安装 quarto${NC}" >&2
    exit 1
fi

# ─── ensure gbt9704 extension ≥ v0.7.0 ───
_init_extension() {
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # Check common install locations
    for d in "_extensions/songwupei/gbt9704" "_extensions/gbt9704"; do
        if [ -f "$d/_extension.yml" ]; then
            echo "✅ gbt9704 扩展已就绪"
            return 0
        fi
    done

    # Install via quarto add
    echo "📦 安装 $EXT_NAME ..."
    if ! quarto add "$EXT_NAME" --no-prompt 2>&1; then
        echo -e "${RED}❌ 扩展安装失败: $EXT_NAME${NC}" >&2
        echo "   请检查网络连接，或手动运行:" >&2
        echo "   cd $WORK_DIR && quarto add $EXT_NAME" >&2
        exit 1
    fi
    echo "✅ 扩展已安装"
}
_init_extension

# ─── copy input + resources to workdir ───
cp "$INPUT_FILE" "$WORK_DIR/$INPUT_FILENAME"
[ -d "$ORIG_DIR/images" ] && cp -r "$ORIG_DIR/images" "$WORK_DIR/images" 2>/dev/null || true

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

# ─── generate filter intermediate (.gbt9704.md) ───
FILTER_DIR="$WORK_DIR/_extensions/songwupei/gbt9704/assets/filters"
echo ""
echo "📋 生成 .gbt9704.md（filter 处理后的中间 markdown）..."
if pandoc "$INPUT_FILENAME" \
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

# ─── detect format prefix ───
_detect_format_prefix() {
    local file="$1"
    local base_fmt="$2"
    if [ -f "$file" ]; then
        if sed -n '/^---$/,/^---$/p' "$file" | grep -qE "gbt9704-${base_fmt}"; then
            echo "gbt9704-${base_fmt}"
            return
        fi
    fi
    echo "gbt9704-${base_fmt}"
}

# ─── render one format ───
_render() {
    local fmt="$1"
    local to_fmt=$(_detect_format_prefix "$INPUT_FILENAME" "$fmt")
    echo "🖨️  quarto render --to $to_fmt ..."
    if ! quarto render "$INPUT_FILENAME" --to "$to_fmt" 2>&1; then
        echo -e "${RED}❌ $fmt 渲染失败${NC}" >&2
        return 1
    fi
}

# ─── render + copy (each format independently; one failure won't block the other) ───
PPTX_OK=false
BEAMER_OK=false

if [ "$FORMAT" = "pptx" ]; then
    echo "🎯 PPTX + Beamer PDF"
    echo ""

    # --- PPTX ---
    if _render pptx; then
        OUT="$WORK_DIR/${INPUT_BASENAME}.pptx"
        if [ -f "$OUT" ]; then
            cp "$OUT" "$ORIG_DIR/"
            echo "📤 PPTX → $ORIG_DIR/${INPUT_BASENAME}.pptx"
            PPTX_OK=true
        fi
    fi

    # --- Beamer ---
    if _render beamer; then
        [ -f "$WORK_DIR/${INPUT_BASENAME}.pdf" ] && mv "$WORK_DIR/${INPUT_BASENAME}.pdf" "$WORK_DIR/${BEAMER_NAME}.pdf"
        OUT="$WORK_DIR/${BEAMER_NAME}.pdf"
        if [ -f "$OUT" ]; then
            cp "$OUT" "$ORIG_DIR/"
            echo "📤 PDF  → $ORIG_DIR/${BEAMER_NAME}.pdf"
            BEAMER_OK=true
        fi
        # 保留 beamer 中间 .tex 文件
        if [ -f "$WORK_DIR/${INPUT_BASENAME}.tex" ]; then
            cp "$WORK_DIR/${INPUT_BASENAME}.tex" "$ORIG_DIR/${BEAMER_NAME}.tex"
            echo "📤 TEX  → $ORIG_DIR/${BEAMER_NAME}.tex"
        fi
    fi
else
    echo "🎯 Beamer PDF"
    echo ""

    if _render beamer; then
        [ -f "$WORK_DIR/${INPUT_BASENAME}.pdf" ] && mv "$WORK_DIR/${INPUT_BASENAME}.pdf" "$WORK_DIR/${BEAMER_NAME}.pdf"
        OUT="$WORK_DIR/${BEAMER_NAME}.pdf"
        if [ -f "$OUT" ]; then
            cp "$OUT" "$ORIG_DIR/"
            echo "📤 PDF  → $ORIG_DIR/${BEAMER_NAME}.pdf"
            BEAMER_OK=true
        fi
        # 保留 beamer 中间 .tex 文件
        if [ -f "$WORK_DIR/${INPUT_BASENAME}.tex" ]; then
            cp "$WORK_DIR/${INPUT_BASENAME}.tex" "$ORIG_DIR/${BEAMER_NAME}.tex"
            echo "📤 TEX  → $ORIG_DIR/${BEAMER_NAME}.tex"
        fi
    fi
fi

# ─── copy filter intermediate + cleaned source ───
if [ -f "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" ]; then
    cp "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" "$ORIG_DIR/"
    echo "📤 MD   → $ORIG_DIR/${INPUT_BASENAME}.gbt9704.md"
fi
GB9704_QMD="${INPUT_BASENAME}.gbt9704.qmd"
if [ -f "$ORIG_DIR/$INPUT_FILENAME" ]; then
    cp "$ORIG_DIR/$INPUT_FILENAME" "$ORIG_DIR/$GB9704_QMD"
    echo "📤 QMD  → $ORIG_DIR/$GB9704_QMD"
fi

# ─── summary ───
echo ""
if $PPTX_OK && $BEAMER_OK; then
    echo "✅ PPTX + Beamer 全部完成!"
elif $PPTX_OK; then
    echo -e "⚠️  PPTX 完成，Beamer 失败（${YELLOW}请检查 xelatex 是否安装、beamer  preamble 是否存在${NC}）"
elif $BEAMER_OK; then
    echo -e "⚠️  Beamer 完成，PPTX 失败"
else
    echo -e "${RED}❌ 全部渲染失败${NC}" >&2
fi

# ─── cleanup ───
rm -f "$WORK_DIR/$INPUT_FILENAME" 2>/dev/null || true
rm -f "$WORK_DIR/${INPUT_BASENAME}.pptx" 2>/dev/null || true
rm -f "$WORK_DIR/${INPUT_BASENAME}.pdf" 2>/dev/null || true
rm -f "$WORK_DIR/${BEAMER_NAME}.pdf" 2>/dev/null || true
rm -f "$WORK_DIR/${INPUT_BASENAME}.tex" 2>/dev/null || true
rm -f "$WORK_DIR/${INPUT_BASENAME}.gbt9704.md" 2>/dev/null || true
rm -f "$WORK_DIR/${INPUT_BASENAME}.qmd" 2>/dev/null || true
rm -rf "$WORK_DIR/images" 2>/dev/null || true
