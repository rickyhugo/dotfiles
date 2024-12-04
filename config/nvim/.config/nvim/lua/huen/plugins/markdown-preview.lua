return {
	"iamcco/markdown-preview.nvim",
	build = function()
		vim.fn["mkdp#util#install"]()
	end,
	event = "BufRead",
	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	ft = { "markdown" },
	keys = { { "<leader>mp", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview" } },
}
