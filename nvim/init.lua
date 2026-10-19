require("config.set")
require("config.remap")
require("config.diagnostics")

-- Register hooks before the first vim.pack.add(), including lockfile installs.
vim.api.nvim_create_autocmd("PackChanged", {
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if name == "nvim-treesitter" and kind == "update" then
			if not ev.data.active then
				vim.cmd.packadd("nvim-treesitter")
			end
			vim.cmd("TSUpdate")
			vim.cmd("TSInstall all")
		end

		if name == "telescope-fzf-native.nvim" and (kind == "install" or kind == "update") then
			vim.system({ "make" }, { cwd = ev.data.path }):wait()
		end

		if name == "peek.nvim" and (kind == "install" or kind == "update") then
			local result = vim.system({ "deno", "task", "--quiet", "build:fast" }, { cwd = ev.data.path }):wait()
			if result.code ~= 0 then
				vim.notify("peek.nvim build failed: " .. result.stderr, vim.log.levels.ERROR)
			end
		end
	end,
})
