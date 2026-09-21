local M = {}
local labels = { lsp = "Language servers", formatters = "Formatters", linters = "Linters", settings = "Settings" }

local function row(name, status, highlight, action, icon, detail)
	return {
		text = name .. "  " .. status .. (detail and ("  " .. detail) or ""),
		name = name,
		status = status,
		highlight = highlight,
		action = action,
		icon = icon or "›",
		detail = detail,
	}
end

local function select(items, title, hint)
	require("snacks").picker.select(items, {
		prompt = title,
		format_item = function(item, chunks)
			if not chunks then
				return item.text
			end
			return {
				{ item.icon .. "  ", item.highlight },
				{ string.format("%-24s", item.name), "Title" },
				{ "  " .. item.status, item.highlight },
				{ item.detail and ("  · " .. item.detail) or "", "Comment" },
			}
		end,
		snacks = {
			layout = { preset = "select", layout = { width = 0.85, max_width = 140, border = "rounded" } },
			win = { input = { footer = hint, footer_pos = "center" } },
		},
	}, function(item)
		if item and item.action then
			item.action()
		end
	end)
end

local function summary(items, kind)
	local active, available, missing = {}, 0, 0
	for _, item in ipairs(items) do
		if item.enabled or item.running then
			local suffix = ""
			if item.available == false then
				suffix = " (unavailable)"
				missing = missing + 1
			elseif kind == "lsp" and not item.running then
				suffix = " (not attached)"
			end
			active[#active + 1] = item.name .. suffix
		elseif item.available then
			available = available + 1
		end
	end
	local text = #active > 0 and table.concat(active, kind == "formatters" and " → " or ", ") or "none enabled"
	return text, available, missing
end

function M.open(bufnr, section, show_missing)
	local tools = require("config.project-tools")
	local view = tools.inspect(bufnr)
	local title = vim.fs.basename(view.root) .. "  /  " .. (view.ft ~= "" and view.ft or "no filetype")
	local function open(next_section, missing)
		tools.pick(bufnr, next_section, missing)
	end
	local items = {}
	if not section then
		for _, kind in ipairs({ "lsp", "formatters", "linters" }) do
			local text, available, missing = summary(view[kind], kind)
			local detail = available .. " available"
			if kind == "formatters" then
				if view.uses_lsp then
					text = "LSP formatting" .. (view.lsp_format == "prefer" and " (preferred)" or " (fallback)")
				end
				detail = (view.autoformat and "on save" or "manual only") .. " · " .. detail
			elseif kind == "lsp" then
				detail = "attached to this buffer · " .. detail
			else
				detail = "on read/save · " .. detail
			end
			items[#items + 1] = row(labels[kind], text, missing > 0 and "DiagnosticWarn" or "DiagnosticOk", function()
				open(kind)
			end, "›", detail)
		end
		items[#items + 1] = row("Settings", "Autoformat " .. (view.autoformat and "on" or "off"), "Comment", function()
			open("settings")
		end, "›", "LSP formatting " .. view.lsp_format .. " · reset defaults")
		select(items, "Project tools · " .. title, " Enter: manage category  ·  Esc: close ")
		return
	end

	local candidates = vim.deepcopy(view[section])
	if section ~= "settings" then
		table.sort(candidates, function(a, b)
			local function rank(item)
				return (item.enabled or item.running) and 0 or (item.available and 1 or 2)
			end
			if rank(a) ~= rank(b) then
				return rank(a) < rank(b)
			end
			if a.step and b.step then
				return a.step < b.step
			end
			return a.name < b.name
		end)
	end
	local hidden = 0
	for _, item in ipairs(candidates) do
		if item.enabled or item.running or item.available or show_missing or section == "settings" then
			local highlight = item.available == false and "DiagnosticWarn"
				or ((item.enabled or item.running) and "DiagnosticOk" or "Comment")
			local status = item.status
			if item.step then
				status = "step " .. item.step .. " · " .. status
			end
			items[#items + 1] = row(item.name, status, highlight, function()
				item.toggle()
				open(section, show_missing)
			end, item.enabled and "●" or "○", item.detail)
		else
			hidden = hidden + 1
		end
	end
	if hidden > 0 or show_missing then
		items[#items + 1] = row(
			show_missing and "Hide unavailable tools" or "Show unavailable tools",
			hidden > 0 and tostring(hidden) or "",
			"Comment",
			function()
				open(section, not show_missing)
			end
		)
	end
	if section == "settings" then
		items[#items + 1] = row("Reset repository to defaults", "", "Comment", function()
			view.reset()
			open()
		end)
	end
	items[#items + 1] = row("Back to overview", "", "Comment", function()
		open()
	end, "←")
	local hint = section == "linters" and " Standalone linters; LSPs may also publish diagnostics.  Enter: toggle "
		or " ● enabled  ○ disabled  ·  Enter: toggle  ·  Esc: close "
	select(items, labels[section] .. " · " .. title, hint)
end

return M
