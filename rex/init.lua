local picker = require("project-picker")
picker.setup({
	roots = {
		"~/anyfin",
		"~/personal",
		"~/.dotfiles",
	},
})

rex.bind("cmd+d", "pane.split", { direction = "right" })
rex.bind("cmd+shift+f", "project_picker")
rex.bind("cmd+shift+d", "session_picker")
