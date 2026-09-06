# quarto.yazi · 一键 GB/T 9704 排版

[![Version](https://img.shields.io/badge/version-0.7.4-blue)](https://codeberg.org/songwupei/quarto.yazi)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A Yazi plugin to render `.typ` / `.md` / `.qmd` files into **GB/T 9704** format with a single keypress.

Yazi 插件：一键将 `.typ` / `.md` / `.qmd` 文件渲染为 **GB/T 9704** 格式。

## Install · 安装

### A: ya pkg (recommended · 推荐, Yazi ≥ 25.5.31)

```sh
ya pkg add songwupei/quarto.yazi:quarto

# 添加快捷键（在 ~/.config/yazi/keymap.toml 中 [mgr] 段任意位置插入）
cat >> ~/.config/yazi/keymap.toml << 'EOF'
[[mgr.prepend_keymap]]
on = ["R"]
run = "plugin quarto"
desc = "Render .typ/.md/.qmd → GB/T 9704 PDF + more"
EOF
```

Then restart Yazi or reload config.

### B: Manual · 手动

```bash
git clone https://codeberg.org/songwupei/quarto.yazi.git ~/.config/yazi/plugins/quarto.yazi
```

## Keymap · 快捷键

Add to `~/.config/yazi/keymap.toml` under `[mgr]`:

```toml
[[mgr.prepend_keymap]]
on = ["R"]
run = "plugin quarto"
desc = "Render .typ/.md/.qmd → GB/T 9704 PDF + more"
```

## Usage · 使用

Hover on a file in Yazi and press **`R`** (`Shift+r`).

在 Yazi 中选中文件，按 **`R`**。

| File type · 文件类型 | Engine · 引擎 | Output · 输出 |
|---|---|---|
| `.typ` | typst | PDF + PNG |
| `.md` | quarto | PDF + DOCX + HTML + PNG |
| `.qmd` | quarto | PDF + DOCX + HTML + PNG |

## Pipeline · 管线

### Typst 管线

```
.typ 文件
  │
  ▼
typst compile
  ├─ → .pdf  (native · 原生)
  └─ → .png  (single page or multi-page · 单页或多页逐页)
```

### Quarto 管线

```
.md / .qmd 文件
  │
  ▼
~/.yazi-quarto/
├─ quarto-gbt9704 extension (auto-installed · 自动安装，≥ v0.7.7)
│    安装源: songwupei/quarto-gbt9704@dist（CI 物化分支，浮动指向最新发布）
│    手动升级: cd ~/.yazi-quarto && quarto update songwupei/quarto-gbt9704@dist --no-prompt
└─ quarto render
    ├─ --to gbt9704-pdf  (xelatex)
    ├─ --to gbt9704-docx
    ├─ --to gbt9704-html → Chrome headless → PNG
    ├─ --to gbt9704-pptx (蓝色商务)
    └─ --to gbt9704-beamer (青山绿水)
        │
        ▼
 output: .pdf + .docx + .html + .png + .pptx → source dir
```

## Config · 配置

### Typst 配置

```bash
# Enable/disable PNG output · 是否输出 PNG（默认 true）
# Set false to output PDF only · false 仅输出 PDF
export TYPST_PNG=true

# PNG output mode · PNG 输出模式
#   multi  — one PNG per page (default · 默认，逐页)
#   single — first page only (仅首页)
export TYPST_PNG_MODE=multi

# PNG resolution · PNG 分辨率 (default · 默认 300)
export TYPST_PNG_PPI=300
```

### Quarto 配置

```bash
# Override quarto render script path · 覆盖 quarto 渲染脚本路径
export FORGE_RENDER_SCRIPT=/path/to/quarto-render.sh
```

## Dependencies · 依赖

| Dependency | Note |
|---|---|
| [Yazi](https://yazi-rs.github.io/) | Terminal file manager（≥ 25.5.31） |
| [typst](https://typst.app/) | Typst compiler (for `.typ` files) |
| [typst-gbt9704](https://codeberg.org/songwupei/typst-gbt9704) | GB/T 9704 Typst package ≥ v0.2.0 |
| [quarto](https://quarto.org/docs/get-started/) | Document rendering engine (for `.md`/`.qmd` files) |
| [quarto-gbt9704](https://github.com/songwupei/quarto-gbt9704) | GB/T 9704 + slides format extension ≥ v0.7.7 (auto-installed) |

## License · 许可证

MIT — see [LICENSE](LICENSE)
