#!/bin/bash
# ============================================================
# typst-render.sh — Yazi quarto 插件 Typst 渲染脚本
#
# 基于 typst + typst-gbt9704 包，无中间文件：
#
#   .typ → typst compile → PDF + PNG
#
# 工作流：
#   1. 检查 typst 是否安装
#   2. typst compile file.typ → PDF（源文件同目录）
#   3. typst compile file.typ → PNG（多页逐页或仅首页）
#   4. 通知结果
#
# Usage: typst-render.sh <file_path>
#
# 配置（环境变量）：
#   TYPST_PNG        是否输出 PNG，默认 true。设 false 仅输出 PDF
#   TYPST_PNG_MODE   multi（默认，逐页）| single（仅首页）
#   TYPST_PNG_PPI    分辨率，默认 300
# ============================================================
set -euo pipefail

# ─── 颜色 ───
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── 配置 ───
PNG_ENABLED="${TYPST_PNG:-true}"
PNG_MODE="${TYPST_PNG_MODE:-multi}"
PNG_PPI="${TYPST_PNG_PPI:-300}"

# ─── 参数检查 ───
if [ $# -lt 1 ]; then
    echo -e "${RED}❌ 用法: $0 <file_path>${NC}" >&2
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}❌ 文件不存在: $INPUT_FILE${NC}" >&2
    exit 1
fi

INPUT_FILENAME=$(basename "$INPUT_FILE")
INPUT_BASENAME="${INPUT_FILENAME%.*}"
INPUT_EXT="${INPUT_FILENAME##*.}"
ORIG_DIR=$(realpath "$(dirname "$INPUT_FILE")")

echo "📄 输入文件: $INPUT_FILENAME  (.${INPUT_EXT})"
echo "📁 输出目录: $ORIG_DIR"

# ─── 检查 typst ───
if ! command -v typst &>/dev/null; then
    echo -e "${RED}❌ 未安装 typst${NC}" >&2
    echo "   安装方法: https://github.com/typst/typst#installation" >&2
    exit 1
fi
echo "✅ typst: $(typst --version 2>/dev/null || echo 'ok')"

cd "$ORIG_DIR"

# ─── 编译 PDF ───
echo ""
echo "🖨️  typst compile → PDF ..."
if typst compile --ppi "$PNG_PPI" "$INPUT_FILENAME" "${INPUT_BASENAME}.pdf" 2>&1; then
    echo "   ✓ PDF 完成"
    PDF_OK=true
else
    echo -e "${RED}❌ PDF 编译失败${NC}" >&2
    exit 1
fi

# ─── 编译 PNG ───
PNG_OK=false
if [ "$PNG_ENABLED" = "true" ]; then
    echo "🖼️  typst compile → PNG (mode=$PNG_MODE, ppi=$PNG_PPI) ..."
    if [ "$PNG_MODE" = "single" ]; then
        if typst compile --pages 1 --ppi "$PNG_PPI" "$INPUT_FILENAME" "${INPUT_BASENAME}.png" 2>&1; then
            echo "   ✓ PNG 完成（首页）"
            PNG_OK=true
        else
            echo -e "  ${YELLOW}⚠  PNG 编译失败${NC}"
        fi
    else
        # multi: typst 需要 {0p} 页码模板 → file_01.png, file_02.png ...
        if typst compile --ppi "$PNG_PPI" "$INPUT_FILENAME" "${INPUT_BASENAME}_{0p}.png" 2>&1; then
            png_count=$(ls "${INPUT_BASENAME}"_*.png 2>/dev/null | wc -l)
            echo "   ✓ PNG 完成（${png_count} 页）"
            PNG_OK=true
        else
            echo -e "  ${YELLOW}⚠  PNG 编译失败${NC}"
        fi
    fi
else
    echo "⏭️  跳过 PNG（TYPST_PNG=$PNG_ENABLED）"
fi

# ─── 输出摘要 ───
echo ""
COPIED=""
if [ -f "${INPUT_BASENAME}.pdf" ]; then
    COPIED="${COPIED}PDF "
fi
if [ "$PNG_OK" = true ]; then
    COPIED="${COPIED}PNG "
fi

if [ -z "$COPIED" ]; then
    echo -e "${RED}❌ 没有生成输出文件${NC}" >&2
    exit 1
fi

echo "📤 ${COPIED}→ ${ORIG_DIR}"
echo "✅ 完成!"
