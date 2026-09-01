#!/usr/bin/env bash
# ============================================================
# install.sh — quarto.yazi 一键安装脚本
#
# 功能:
#   1. 自动检测项目根目录
#   2. 创建 Yazi 插件符号链接
#   3. 检查 quarto 是否已安装
#   4. 可选：自动添加快捷键到 keymap.toml
#   5. 安装后自检并给出彩色摘要
#
# 用法:
#   bash install.sh                   # 交互模式
#   bash install.sh --no-keymap       # 跳过快捷键配置
#   bash install.sh --yes             # 全部自动确认（非交互）
# ============================================================
set -euo pipefail

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── 全局状态 ───
WARNINGS=()
ERRORS=()
TODO=()
INSTALLED_COMPONENTS=()

# ─── 参数解析 ───
SKIP_KEYMAP=false
AUTO_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-keymap)
            SKIP_KEYMAP=true
            shift
            ;;
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --no-keymap       跳过快捷键配置"
            echo "  --yes, -y         全部自动确认（非交互模式）"
            echo "  --help, -h        显示帮助"
            exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}（使用 --help 查看帮助）"
            exit 1
            ;;
    esac
done

# ─── 辅助函数 ───
_confirm() {
    local prompt="$1"
    if $AUTO_YES; then
        echo -e "  ${YELLOW}⚡ 自动确认: $prompt${NC}"
        return 0
    fi
    echo -ne "  ${CYAN}? $prompt [y/N] ${NC}"
    read -r REPLY
    case "$REPLY" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

_step() {
    echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"
}

_success() {
    echo -e "  ${GREEN}✓${NC} $1"
    INSTALLED_COMPONENTS+=("$1")
}

_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARNINGS+=("$1")
}

_error() {
    echo -e "  ${RED}❌${NC} $1"
    ERRORS+=("$1")
}

_check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        _error "$1 未安装"
        TODO+=("安装 $1")
        return 1
    fi
    return 0
}

# ════════════════════════════════════════════════════════════
# 步骤 0: 检测项目根目录 & 环境
# ════════════════════════════════════════════════════════════
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_SRC="$PROJECT_DIR/quarto.yazi"
QUARTO_SCRIPT="$PLUGIN_SRC/assets/quarto-render.sh"
TYPST_SCRIPT="$PLUGIN_SRC/assets/typst-render.sh"
MAIN_LUA="$PLUGIN_SRC/main.lua"

YAZI_CONFIG="${YAZI_CONFIG_HOME:-$HOME/.config/yazi}"
PLUGIN_DST="$YAZI_CONFIG/plugins/quarto.yazi"
KEYMAP_FILE="$YAZI_CONFIG/keymap.toml"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║     quarto.yazi  跨电脑安装             ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
_info "项目目录 : ${GREEN}$PROJECT_DIR${NC}"
_info "用户配置  : ${GREEN}$YAZI_CONFIG${NC}"

# 校验项目完整性
for f in "$MAIN_LUA" "$QUARTO_SCRIPT" "$TYPST_SCRIPT"; do
    if [ ! -f "$f" ]; then
        _error "项目文件缺失: $f（请确保在完整的 git 仓库中运行）"
        exit 1
    fi
done

# 检测 yazi
_check_cmd "yazi"

# ════════════════════════════════════════════════════════════
# 步骤 1: 安装 Yazi 插件符号链接
# ════════════════════════════════════════════════════════════
_step "安装 Yazi 插件"

mkdir -p "$YAZI_CONFIG/plugins"

if [ -L "$PLUGIN_DST" ]; then
    current_target="$(readlink -f "$PLUGIN_DST" 2>/dev/null || readlink "$PLUGIN_DST")"
    if [ "$current_target" = "$PLUGIN_SRC" ]; then
        _success "插件链接已正确安装"
    else
        _warn "已有链接指向: $current_target"
        if _confirm "替换指向当前项目 ($PLUGIN_SRC)？"; then
            rm "$PLUGIN_DST"
            ln -s "$PLUGIN_SRC" "$PLUGIN_DST"
            _success "已更新插件链接 → $PLUGIN_SRC"
        fi
    fi
elif [ -d "$PLUGIN_DST" ]; then
    _warn "目标位置是普通目录（非符号链接）: $PLUGIN_DST"
    if _confirm "删除旧目录并创建符号链接？"; then
        rm -rf "$PLUGIN_DST"
        ln -s "$PLUGIN_SRC" "$PLUGIN_DST"
        _success "已替换为插件链接 → $PLUGIN_SRC"
    else
        _info "跳过插件安装"
    fi
elif [ -e "$PLUGIN_DST" ]; then
    _error "目标位置已存在文件: $PLUGIN_DST"
    exit 1
else
    ln -s "$PLUGIN_SRC" "$PLUGIN_DST"
    _success "插件链接: $PLUGIN_DST → $PLUGIN_SRC"
fi

# ════════════════════════════════════════════════════════════
# 步骤 2: 检查 quarto 和 typst
# ════════════════════════════════════════════════════════════
_step "检查 quarto"

if command -v quarto &>/dev/null; then
    _success "quarto: $(quarto --version 2>/dev/null || echo 'installed')"
else
    _warn "未安装 quarto（.md/.qmd 渲染将无法使用）"
    _info "安装方法: https://quarto.org/docs/get-started/"
    TODO+=("安装 quarto: https://quarto.org/docs/get-started/")
fi

_step "检查 typst"

if command -v typst &>/dev/null; then
    _success "typst: $(typst --version 2>/dev/null || echo 'installed')"
else
    _warn "未安装 typst（.typ 渲染将无法使用）"
    _info "安装方法: https://github.com/typst/typst#installation"
    TODO+=("安装 typst: https://github.com/typst/typst#installation")
fi

# ════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════
# 步骤 3: 预安装 quarto-gbt9704 扩展
# ════════════════════════════════════════════════════════════

WORK_DIR="$HOME/.yazi-quarto"
mkdir -p "$WORK_DIR"

if [ -f "$WORK_DIR/_extensions/songwupei/gbt9704/_extension.yml" ]; then
	_installed_ver=$(grep -oP 'version:\\s*\\K[0-9.]+' "$WORK_DIR/_extensions/songwupei/gbt9704/_extension.yml" 2>/dev/null || echo "?")
	_success "quarto-gbt9704 扩展已存在 (v${_installed_ver})"
	if _confirm "检查并更新扩展到最新版？"; then
		_info "正在更新..."
		quarto add songwupei/quarto-gbt9704 --no-prompt 2>/dev/null && _success "扩展已更新" || _warn "更新失败，当前版本继续可用"
	fi
else
	_info "正在下载 quarto-gbt9704（仅此一次，需联网）..."
	if quarto add songwupei/quarto-gbt9704 --no-prompt 2>&1; then
		_success "quarto-gbt9704 扩展已预安装"
	else
		_warn "扩展下载失败，首次渲染时将自动重试"
	fi
fi
# 步骤 4: 快捷键配置
# ════════════════════════════════════════════════════════════
_step "快捷键配置"

KEYMAP_ENTRY='[[mgr.prepend_keymap]]
on = ["R"]
run = "plugin quarto"
desc = "Render .typ/.md/.qmd → GB/T 9704 PDF + more"'

if $SKIP_KEYMAP; then
    _info "已跳过快捷键配置 (--no-keymap)"
elif [ -f "$KEYMAP_FILE" ]; then
    if grep -q "quarto" "$KEYMAP_FILE"; then
        _success "快捷键 R 已配置为 quarto"
    elif grep -q 'on = \["R"\]' "$KEYMAP_FILE" || grep -q 'on = "R"' "$KEYMAP_FILE"; then
        _warn "快捷键 R 已被其他插件占用"
        if _confirm "仍添加 quarto（需手动修改 keymap 解决冲突）？"; then
            echo "" >> "$KEYMAP_FILE"
            echo "$KEYMAP_ENTRY" >> "$KEYMAP_FILE"
            _success "已添加（注意：keymap 中有重复的 R 快捷键）"
        else
            _info "跳过快捷键配置"
        fi
    else
        if _confirm "添加快捷键 R（在 keymap.toml 的 [mgr] 中）？"; then
            if grep -q '^\[mgr\]' "$KEYMAP_FILE"; then
                echo "" >> "$KEYMAP_FILE"
                echo "$KEYMAP_ENTRY" >> "$KEYMAP_FILE"
            else
                echo "" >> "$KEYMAP_FILE"
                echo "[mgr]" >> "$KEYMAP_FILE"
                echo "$KEYMAP_ENTRY" >> "$KEYMAP_FILE"
            fi
            _success "已添加快捷键 R（重启 yazi 后生效）"
        else
            _info "跳过快捷键配置"
            TODO+=("手动添加 keymap: 编辑 $KEYMAP_FILE，参考 README.md")
        fi
    fi
else
    _warn "$KEYMAP_FILE 不存在（yazi 尚未初始化？）"
    TODO+=("初始化 yazi 后再运行本脚本添加 keymap")
fi

# ════════════════════════════════════════════════════════════
# 安装摘要
# ════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║            安装摘要                      ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BOLD}已安装组件:${NC}"
for c in "${INSTALLED_COMPONENTS[@]}"; do
    echo -e "  ${GREEN}✓${NC} $c"
done

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${YELLOW}警告:${NC}"
    for w in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $w"
    done
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${RED}错误:${NC}"
    for e in "${ERRORS[@]}"; do
        echo -e "  ${RED}❌${NC} $e"
    done
fi

if [ ${#TODO[@]} -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${CYAN}待完成:${NC}"
    for t in "${TODO[@]}"; do
        echo -e "  ${CYAN}→${NC} $t"
    done
fi

echo ""
echo -e "${BOLD}环境变量（可选）:${NC}"
echo -e "  export FORGE_RENDER_SCRIPT=${QUARTO_SCRIPT}"
echo -e "  export TYPST_RENDER_SCRIPT=${TYPST_SCRIPT}"
echo -e "  export TYPST_PNG_MODE=multi    # multi（逐页）| single（仅首页）"
echo -e "  export TYPST_PNG_PPI=300       # PNG 分辨率"

echo ""
echo -e "${GREEN}${BOLD}安装完成！${NC}"
echo "  在 Yazi 中选中 .typ / .md / .qmd 文件，按 ${BOLD}R${NC} 渲染。"
echo "  .typ → typst compile → PDF + PNG"
echo "  .md/.qmd → quarto render → PDF + DOCX + HTML + PNG"
echo "  首次运行 quarto 时会自动在 ~/.yazi-quarto/ 安装 quarto-gbt9704 扩展。"

if [ ${#ERRORS[@]} -gt 0 ]; then
    exit 1
fi
exit 0
