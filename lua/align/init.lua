local M = {}

local align_win = require 'align.align_win'

local function clamp(x, a, b)
	return math.max(a, math.min(x, b))
end

local function find_indices_of_alignments(line, alignments)
	local indices = {}
	for _, alignment in ipairs(alignments) do
		local init = 1
		while init <= #line do
			local start_i, end_i = line:find(alignment, init)
			if start_i == nil then break end
			table.insert(indices, { i = start_i, val = alignment })
			init = end_i + 1
		end
	end
	-- NOTE: stable since equality is only signaled for value equality.
	table.sort(indices, function(a, b)
		if a.i == b.i then return a.val < b.val end
		return a.i < b.i
	end)
	return indices
end

local function align(buf, state)
	local lines = vim.api.nvim_buf_get_lines(
		buf, state.start - 1, state.stop, false)
	if vim.tbl_isempty(lines) then return end

	---@cast lines {i: number, val: string}[][]
	for i, raw_line in ipairs(lines) do
		lines[i] = find_indices_of_alignments(raw_line, M.opts.align)
	end

	local min_i = 1
	while not vim.tbl_isempty(lines[min_i]) do
		local line_nr = state.start - 3 + min_i
		if line_nr < 0 then break end
		min_i = min_i - 1
		lines[min_i] = find_indices_of_alignments(vim.api.nvim_buf_get_lines(
			buf, line_nr, line_nr + 1, true)[1], M.opts.align)
	end
	local max_i = state.stop - state.start + 1
	while not vim.tbl_isempty(lines[max_i]) do
		local line_nr = state.start - 1 + max_i
		if line_nr >= state.len then break end
		max_i = max_i + 1
		lines[max_i] = find_indices_of_alignments(vim.api.nvim_buf_get_lines(
			buf, line_nr, line_nr + 1, true)[1], M.opts.align)
	end

	for _, window in ipairs(vim.fn.win_findbuf(buf)) do
		align_win {
			buf = buf,
			window = window,
			lines = lines,
			state = state,
			min_i = min_i,
			max_i = max_i,
		}
	end
end

function M.trigger(buf, start, stop, force)
	local len = vim.api.nvim_buf_line_count(buf)
	local state = vim.b[buf].align_state or { start = math.huge, stop = 0, len = len }
	local removed = math.max(0, state.len - len)
	-- NOTE: align one extra line on both sides
	state.start = clamp(start - 1, 1, state.start)
	state.stop = clamp(stop + 1, state.stop - removed, len)
	state.len = len

	if force == true
		or vim.tbl_isempty(M.opts.update_in_modes)
		or vim.tbl_contains(M.opts.update_in_modes, vim.api.nvim_get_mode().mode) then
		align(buf, state)
		vim.b[buf].align_state = nil
	else
		vim.b[buf].align_state = state
	end
end

local default_opts = {
	-- `array` of `modes` (output of `nvim_get_mode().mode` (`n`, `i`, ...)).
	-- Leave empty if you want to always update the alignments.
	update_in_modes = {},
	align = { ' = ', '\t' }, -- `table` of patterns to align.
}

function M.setup(opts)
	if not vim.fn.has 'nvim-0.10' then error 'Requires nvim version >= 0.10.x' end

	local augroup = vim.api.nvim_create_augroup('align', {})
	local ns_id = vim.api.nvim_create_namespace 'align'

	M.opts = vim.tbl_deep_extend('force', default_opts, opts or {})

	vim.api.nvim_set_hl(ns_id, 'Alignment', { link = 'Conceal' })
	vim.api.nvim_set_hl_ns(ns_id)
	vim.api.nvim_create_autocmd(
		{ 'BufRead', 'TextChanged', 'TextChangedI', 'TextChangedP', 'InsertLeave', 'BufWinEnter' }, {
			group = augroup,
			desc = 'Update text alignment',
			callback = function(event) M.trigger(event.buf, vim.fn.getpos "'["[2], vim.fn.getpos "']"[2], false) end,
		}
	)
	vim.api.nvim_create_autocmd(
		{ 'WinClosed' }, {
			group = augroup,
			desc = 'Delete unneeded alignment namespaces',
			callback = function(event)
				local win_ns_id = tonumber(event.match) or -1 -- NOTE: should never fail
				vim.api.nvim_buf_clear_namespace(event.buf, win_ns_id or 0, 0, -1)
			end,
		}
	)
	for buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then M.trigger(buf, 1, math.huge, true) end
	end
end

return M
