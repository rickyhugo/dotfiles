return {
	"mfussenegger/nvim-treehopper",
	keys = { { "m", mode = { "o", "x" } } },
	config = function()
		vim.cmd([[
        omap     <silent> m :<C-U>lua require('tsht').nodes()<CR>
        xnoremap <silent> m :lua require('tsht').nodes()<CR>
      ]])
	end,
}
