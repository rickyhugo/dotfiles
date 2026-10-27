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
rex.bind("cmd+shift+r", "client.config.reload")

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
rex.bind("cmd+shift+/", "pane.split", { direction = "right" })
rex.bind("cmd+shift+-", "pane.split", { direction = "down" })

-- apps
rex.bind("cmd+shift+f", "project_picker")
rex.bind("cmd+shift+d", "session_picker")
bind_app("cmd+shift+s", "lazygit")
bind_app("cmd+shift+a", "opencode", { os.getenv("HOME") .. "/.opencode/bin" })

-- tabs
for i = 1, 9 do
	rex.bind("cmd+" .. i, "client.tab.goto", { index = i })
end
rex.bind("cmd+0", "client.tab.goto", { index = -1 })
