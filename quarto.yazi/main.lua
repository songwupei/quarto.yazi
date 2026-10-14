--- quarto.yazi v0.7.6
--- Yazi plugin: one-key render .md/.qmd/.typ → GB/T 9704 + slides
--- 快捷键触发 → typst compile 或 quarto render → PDF + DOCX + PPTX + Beamer
---
--- 依赖: typst (typst.app) 或 quarto (quarto.org)
---
--- Keymap / 快捷键:
---   R     → 自动检测格式
---   R + g → 强制 gbt9704（公文 PDF+DOCX+HTML+PNG）
---   R + b → 强制 textbook（教科书 PDF）
---   R + p → 幻灯片 PPTX + Beamer PDF（gbt9704 ≥ v0.7.0）

local M = {}

-- Config dir base / 配置目录基础路径
local CFG = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local PLUGIN_DIR = CFG .. "/yazi/plugins/quarto.yazi"

-- Script paths: env var first, fallback to bundled script / 脚本路径
local QUARTO_SCRIPT = os.getenv("FORGE_RENDER_SCRIPT")
    or (PLUGIN_DIR .. "/assets/quarto-render.sh")

local TYPST_SCRIPT = os.getenv("TYPST_RENDER_SCRIPT")
    or (PLUGIN_DIR .. "/assets/typst-render.sh")

local SLIDES_SCRIPT = os.getenv("SLIDES_RENDER_SCRIPT")
    or (PLUGIN_DIR .. "/assets/quarto-slides-render.sh")

local function extract_error(stderr)
    -- Extract meaningful error lines (skip ANSI/empty, keep last lines)
    local lines = {}
    for line in (stderr or ""):gmatch("[^\r\n]+") do
        local clean = line:gsub("\27%[[0-9;]*[a-zA-Z]", ""):match("^%s*(.-)%s*$")
        if clean and #clean > 0 then
            lines[#lines + 1] = clean
        end
    end
    if #lines == 0 then
        return "Unknown error"
    end
    -- Take last 5 meaningful lines
    local start = math.max(1, #lines - 4)
    local result = {}
    for i = start, #lines do
        result[#result + 1] = lines[i]
    end
    return table.concat(result, "\n")
end

local function extract_summary(stdout)
    -- Extract summary line with 📤
    for line in (stdout or ""):gmatch("[^\r\n]+") do
        local clean = line:gsub("\27%[[0-9;]*[a-zA-Z]", "")
        if clean:match("📤") then
            return clean
        end
    end
    return "Done!"
end

local function run_script(script, file_path, force_fmt, fast)
    local cmd = Command("bash")
        :arg(script)
        :arg(file_path)
    if force_fmt and #force_fmt > 0 then
        cmd = cmd:arg(force_fmt)
    end
    -- fast：只出 PDF（脚本侧读 QUARTO_FAST，跳过 DOCX/HTML/PNG）
    if fast then
        cmd = cmd:env("QUARTO_FAST", "1")
    end
    local output, err_code = cmd
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :output()

    if err_code ~= nil then
        ya.notify({
            title = "Render ✗",
            content = "Script execution failed: " .. tostring(err_code),
            timeout = 6.0,
            level = "error",
        })
        return
    end

    if not output.status.success then
        ya.notify({
            title = "Render ✗",
            content = extract_error(output.stderr),
            timeout = 8.0,
            level = "error",
        })
        return
    end

    ya.notify({
        title = "Render ✓",
        content = extract_summary(output.stdout),
        timeout = 5.0,
        level = "info",
    })
end

local get_hovered = ya.sync(function()
    local h = cx.active.current.hovered
    if not h then
        return nil
    end
    return tostring(h.url)
end)

function M:entry(args)
    -- Extract explicit format override from keymap args (e.g. "gbt9704" or "textbook")
    -- Yazi 26.x: args = {args = {"pptx"}, id = N}
    -- Yazi 25.x: args = {"pptx"} or args = "pptx"
    local force_fmt = nil
    if type(args) == "table" then
        if args.args and type(args.args) == "table" and args.args[1] then
            force_fmt = args.args[1]                -- Yazi 26.x
        elseif args[1] and type(args[1]) == "string" then
            force_fmt = args[1]                     -- Yazi 25.x array
        else
            force_fmt = select(2, next(args))       -- key-value table
        end
    elseif type(args) == "string" and args ~= "" then
        force_fmt = args
    end

    local file_path = get_hovered()

    if not file_path then
        ya.notify({
            title = "Render",
            content = "No file hovered · 未选中文件",
            timeout = 3.0,
            level = "warn",
        })
        return
    end

    -- fast / pdf：只出 PDF 的快速模式（不作为格式参数传下去）
    local fast_mode = (force_fmt == "fast" or force_fmt == "pdf")
    if fast_mode then
        force_fmt = nil
    end

    -- Detect file type and route / 检测文件类型并分流
    local is_typ = file_path:match("%.typ$")
    local is_md = file_path:match("%.md$")
    local is_qmd = file_path:match("%.qmd$")

    local script = nil
    local engine = nil

    -- Route slides formats (pptx/beamer) to slides script
    if force_fmt == "pptx" or force_fmt == "beamer" then
        if is_md or is_qmd then
            script = SLIDES_SCRIPT
            engine = "Slides"
        else
            ya.notify({
                title = "Slides Render",
                content = "仅支持 .md / .qmd:\n" .. file_path,
                timeout = 4.0,
                level = "warn",
            })
            return
        end
    elseif is_typ then
        script = TYPST_SCRIPT
        engine = "Typst"
    elseif is_md or is_qmd then
        script = QUARTO_SCRIPT
        engine = "Quarto"
    else
        ya.notify({
            title = "Render",
            content = "仅支持 .typ / .md / .qmd:\n" .. file_path,
            timeout = 4.0,
            level = "warn",
        })
        return
    end

    -- Show progress notification / 进度通知
    local fname = file_path:match("[^/]+$")
    ya.notify({
        title = "Render · " .. engine,
        content = "⏳ 渲染中...\n" .. fname,
        timeout = 2.0,
        level = "info",
    })

    run_script(script, file_path, force_fmt, fast_mode)
end

return M
