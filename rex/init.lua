-- tmux-style prefix. Change this one line and every prefixed shortcut moves.
local prefix = "ctrl+t"

local function bind_app(key, command, path_prepend)
	rex.action({
		name = "open_" .. command,
		title = "Open " .. command,
		run = function(ctx)
			local process, err = rex.call("block.method", {
				session_id = ctx.session_id,
				block_id = ctx.block_id,
				method = "process",
				args = {},
			})
			assert(process, err)

			local cwd = process.foreground and process.foreground.cwd
			if not cwd or cwd == "" then
				cwd = process.child and process.child.cwd
			end
			assert(cwd and cwd ~= "", "Cannot determine current directory")

			local tab, create_err = rex.session.new_window({
				session_id = ctx.session_id,
				window_label = command,
				focus = true,
				layout = {
					block = {
						flavor = "com.superlogical.terminal.shell",
						options = {
							command = { command },
							path_prepend = path_prepend,
							cwd = cwd,
						},
					},
				},
			})
			assert(tab, create_err)
			local clients, clients_err = rex.call("client.list", { kinds = { "app" }, session_id = ctx.session_id })
			assert(clients, clients_err)
			local client_id
			for _, client in ipairs(clients.clients) do
				if client.client_id == ctx.client_id or #clients.clients == 1 then
					client_id = client.client_id
				end
			end
			assert(client_id, "Cannot identify the Rex app to focus")
			local selected, select_err = rex.call("client.perform", {
				client_id = client_id,
				session_id = ctx.session_id,
				action = "session.select",
				args = {
					session_id = ctx.session_id,
					window_id = tab.window_id,
				},
			})
			assert(selected, select_err)
		end,
	})
	rex.bind(key, "open_" .. command)
end

-- config
rex.bind(prefix .. ">r", "client.config.reload")

-- picker
local picker = require("project-picker")
picker.setup({
	roots = {
		"~/anyfin",
		"~/personal",
		"~/.dotfiles",
	},
})

-- panes
rex.bind(prefix .. ">/", "pane.split", { direction = "right" })
rex.bind(prefix .. ">-", "pane.split", { direction = "down" })

-- apps
rex.bind(prefix .. ">f", "project_picker")
rex.bind(prefix .. ">d", "session_picker")
bind_app(prefix .. ">s", "lazygit")
bind_app(prefix .. ">a", "opencode", { os.getenv("HOME") .. "/.opencode/bin" })

-- tabs
for i = 1, 9 do
	rex.bind("cmd+" .. i, "client.tab.goto", { index = i })
	rex.bind(prefix .. ">" .. i, "client.tab.goto", { index = i })
end
rex.bind("cmd+0", "client.tab.goto", { index = -1 })
rex.bind(prefix .. ">0", "client.tab.goto", { index = -1 })

-- press the prefix twice to send one to the terminal
rex.bind(prefix .. ">" .. prefix, "pane.send_key", { key = prefix })
