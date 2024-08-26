local M = {}

local align_win = require 'align.align_win'

-- TODO:
-- - align strings of different length (choose)
--   - list of pairs of where to place the alignment and what to align
-- - fix alignment of tabs to be like elastic tabstops (`set tabstop=1 vartabstop=`?)
-- - custom function for alignment detection
--   - post processing
--   - entire line
--   - entire buffer
-- - embed alignments
--   - unembed alignments
--   - reembed alignments

local function clamp(x, a, b)
	return math.max(a, math.min(x, b))
end

local function _find_indices_of_alignments(line, alignments, indices, opts)
	for key, alignment in pairs(alignments) do
		if type(key) ~= 'number' then
			-- NOTE:
			-- non number keys are ignored.
			-- why?, wouldn't it be awesome.
			-- filetypes have to be handled extra
		elseif alignment == false then
			-- NOTE: when default alignments are (partially) disabled.
		elseif type(alignment) == 'string' then
			local init = 1
			while init <= #line do
				local start_i, end_i = line:find(alignment, init)
				if start_i == nil then break end
				local align_i
				if opts.align == 'left' or opts.align == nil then
					align_i = start_i
				elseif opts.align == 'right' then
					align_i = end_i
				elseif opts.align == 'center' then
					align_i = math.floor((start_i + end_i) / 2)
				else
					error(('Invalid option for pattern option `align`: `%s`'):format(opts.align))
				end
				table.insert(indices, {
					col = start_i,
					align = align_i,
					key = tostring(alignment),
				})
				init = end_i + 1
			end
		elseif type(alignment) == 'table' then
			_find_indices_of_alignments(line, alignment, indices, {
				align = alignment.align or opts.align,
			})
		end
	end
end
local function find_indices_of_alignments(line, buf, alignments)
	local indices = {}
	if type(line) == 'number' then
		line = vim.api.nvim_buf_get_lines(buf, line, line + 1, true)[1]
	end
	_find_indices_of_alignments(line, alignments, indices, {})
	-- NOTE:
	-- `or` only returns the second when the first is either `nil` or `false` (no default).
	-- I.e. `or` is not used as a null coalescing operator but as the lua `or` operator.
	local ft_alignments = alignments[vim.bo.filetype or ''] or alignments['*']
	if ft_alignments ~= nil then _find_indices_of_alignments(line, ft_alignments, indices, alignments) end

	-- NOTE: stable since equality is only signaled for value equality.
	table.sort(indices, function(a, b)
		if a.col ~= b.col then
			return a.col < b.col
		elseif a.align ~= b.align then
			return a.align < b.align
		else
			return a.key < b.key
		end
	end)
	return indices
end

local function align(buf, state)
	local lines = vim.api.nvim_buf_get_lines(
		buf, state.start - 1, state.stop, false)
	if vim.tbl_isempty(lines) then return end

	---@cast lines {i: number, val: string}[][]
	for i, raw_line in ipairs(lines) do
		lines[i] = find_indices_of_alignments(raw_line, buf, M.opts.align)
	end

	local min_i = 1
	while not vim.tbl_isempty(lines[min_i]) do
		local line_nr = state.start - 3 + min_i
		if line_nr < 0 then break end
		min_i = min_i - 1
		lines[min_i] = find_indices_of_alignments(line_nr, buf, M.opts.align)
	end
	local max_i = state.stop - state.start + 1
	while not vim.tbl_isempty(lines[max_i]) do
		local line_nr = state.start - 1 + max_i
		if line_nr >= state.len then break end
		max_i = max_i + 1
		lines[max_i] = find_indices_of_alignments(line_nr, buf, M.opts.align)
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
	-- `table` of patterns to align.
	-- - `number` (positional) arguments are global alignments.
	-- - `string` arguments are filetype specific.
	--   The key has to be the same as the filetype (value of `vim.opt.filetype`)
	--   or `*` as a fallback.
	--
	-- A pattern can be either:
	-- 1. `false` to disable defaults (usually at index `0`).
	-- 2. A `string` representing a lua pattern which gets leftaligned.
	-- 3. A `function` -- TODO: figure out
	-- 4. A `table` representing multiple patterns with optional properties.
	-- 	  The properties can be:
	-- 	  - `align` which specifies how to align the pattern.
	-- 	    One of `left`, `right` or `center`.
	align = {
		[0] = {
			'\t',
		},
		['*'] = {
			[0] = {
				' = ',
				{ '%s[+-]?[%d.,]*%d', align = 'right' },
			},
		},
		csv = {
			[0] = {
				',',
			},
		},
		yaml = {
			[0] = {
				': ',
			},
		},
		--[[
		-- TODO: figure out functions
		-- maybe:
		function(line)
			-- returning a table with the keys:
			-- - `key` to specify how to compare (and sort)
			-- - <positional>, which represents a tuple of where, and what (ints)
			return {}
		end,
		--]]
	},
}

function M.setup(opts)
	if not vim.fn.has 'nvim-0.10' then error 'Requires nvim version >= 0.10.x' end

	local augroup = vim.api.nvim_create_augroup('align', {})
	local ns_id = vim.api.nvim_create_namespace 'align'

	M.opts = vim.tbl_deep_extend('force', default_opts, opts or {})

	vim.api.nvim_set_hl(ns_id, 'Alignment', { link = 'Comment' })
	vim.api.nvim_set_hl_ns(ns_id)
	vim.api.nvim_create_autocmd(
	-- FIXME: alignment not updated if virtual text is added or removed.
		{ 'TextChanged', 'TextChangedI', 'TextChangedP', 'InsertLeave', 'BufWinEnter' }, {
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
