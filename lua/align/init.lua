local M = {}

local function clamp(x, a, b)
	return math.max(a, math.min(x, b))
end

local function find_indices_of_alignments(line, alignments)
	local indices = {}
	for _, alignment in ipairs(alignments) do
		local init = 1
		while init < #line do
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

local function lcs(x, y, key)
	local function ij(i, j) return i + (#x + 1) * j end
	local lcs_length_for_substrings = {} -- 0-based folded 2d array

	-- NOTE:
	-- inspired by https://en.wikipedia.org/wiki/Longest_common_subsequence_problem#Computing_the_length_of_the_LCS
	-- changes:
	-- - reduce on beginning not end
	local function calc_lcs_length_for_substrings(i, j)
		local _ij = ij(i, j)
		if lcs_length_for_substrings[_ij] ~= nil then
		elseif i > #x or j > #y then
			lcs_length_for_substrings[_ij] = 0
		elseif x[i][key] == y[j][key] then
			lcs_length_for_substrings[_ij] = 1 + calc_lcs_length_for_substrings(i + 1, j + 1)
		else
			lcs_length_for_substrings[_ij] = math.max(
				calc_lcs_length_for_substrings(i + 1, j),
				calc_lcs_length_for_substrings(i, j + 1))
		end
		return lcs_length_for_substrings[ij(i, j)]
	end
	calc_lcs_length_for_substrings(1, 1)

	-- inspired by https://en.wikipedia.org/wiki/Longest_common_subsequence_problem#Reading_out_a_LCS but backwards
	local seq = {}
	local i, j = 1, 1
	while i <= #x and j <= #y do
		if x[i][key] == y[j][key] then
			table.insert(seq, 1, { i, j })
			i, j = i + 1, j + 1
		elseif (lcs_length_for_substrings[ij(i, j + 1)] or 0)
			> (lcs_length_for_substrings[ij(i + 1, j)] or 0) then
			j = j + 1
		else
			i = i + 1
		end
	end
	return seq
end

local function convert_indicies_to_columns_of_alignments(data)
	local converted = {}
	local ei = 1 -- index for `extmarks`
	for i = data.min_i, data.max_i do
		local line_nr = data.state.start - 2 + i
		local shifted = 0
		while data.extmarks[ei] ~= nil
			and data.extmarks[ei][2] < line_nr do
			ei = ei + 1
		end

		converted[i] = {}
		for j, alignment in ipairs(data.lines[i]) do
			while data.extmarks[ei] ~= nil
				and data.extmarks[ei][2] == line_nr
				and data.extmarks[ei][3] < alignment.i do
				for _, text in ipairs(data.extmarks[ei][4].virt_text) do
					-- NOTE: text should only contain spaces
					shifted = shifted + #text[1]
				end
				ei = ei + 1
			end
			local col = vim.fn.virtcol { data.state.start - 1 + i, alignment.i }
			col = col - shifted
			converted[i][j] = { col = col, i = alignment.i, val = alignment.val }
		end
	end
	data.lines = converted
end
---@param data {lines: {[number]: {col: number, val: string, aligned: {col: number, deps: {[table]: boolean}}?}, progress: number?}[], min_i: number, max_i: number}
local function figure_out_sections(data)
	local function normalize_line(i)
		data.lines[i] = vim.tbl_filter(function(alignment) return alignment.aligned ~= nil end, data.lines[i])
		for j = 2, #data.lines[i] do data.lines[i][j].aligned.deps[data.lines[i][j - 1].aligned] = true end
		data.lines[i].progress = 1
	end
	for i = data.min_i, data.max_i - 1 do
		local current, next = data.lines[i], data.lines[i + 1]
		for _, alignment in ipairs(lcs(current, next, 'val')) do
			local j, k = alignment[1], alignment[2]
			local aligned = current[j].aligned or { col = 0, deps = {} }
			current[j].aligned = aligned
			next[k].aligned = aligned
		end
		normalize_line(i)
	end
	normalize_line(data.max_i)
end
---@param data {lines: {[number]: {col: number, val: string, aligned: {col: number, deps: {[table]: boolean}}}, progress: number}[]}
local function align_sections(data)
	-- FIXME:
	-- - align respecting wrapped text
	-- Possible solutions:
	-- - `vim.fn.screenpos`
	--   - Row has to be on screen.

	-- NOTE: copy of lines is intended and required
	local lines = vim.tbl_filter(function(line) return line[line.progress] ~= nil end, data.lines)
	local resolved = {}
	while not vim.tbl_isempty(lines) do
		-- NOTE: assumes that if every dependency is resolved it is the next alignment (line.progress)
		local resolving = {}
		for i, line in pairs(lines) do
			local current = line[line.progress]
			for dep, _ in pairs(current.aligned.deps) do
				if resolved[dep] ~= true then goto continue end
			end
			local last = line[line.progress - 1]
			local shift = last ~= nil and (last.aligned.col - last.col) or 0
			current.aligned.col = math.max(current.aligned.col, current.col + shift)
			line.progress = line.progress + 1
			resolving[current.aligned] = true
			if line.progress > #line then lines[i] = nil end
			::continue::
		end
		resolved = vim.tbl_extend('keep', resolved, resolving)
	end
end
local function apply_alignment(data)
	local ei = 1 -- index for `extmarks`
	for i = data.min_i, data.max_i do
		local line_nr = data.state.start - 2 + i -- 0-based
		local shift = 0
		while data.extmarks[ei] ~= nil
			and data.extmarks[ei][2] < line_nr do
			vim.api.nvim_buf_del_extmark(data.buf, data.ns_id, data.extmarks[ei][1])
			ei = ei + 1
		end
		for _, alignment in ipairs(data.lines[i]) do
			local col = alignment.i - 1
			local delta = alignment.aligned.col - alignment.col - shift
			shift = shift + delta
			while data.extmarks[ei] ~= nil
				and data.extmarks[ei][2] == line_nr
				and data.extmarks[ei][3] < col do
				vim.api.nvim_buf_del_extmark(data.buf, data.ns_id, data.extmarks[ei][1])
				ei = ei + 1
			end
			local new_id = nil
			if data.extmarks[ei] ~= nil
				and data.extmarks[ei][2] == line_nr
				and data.extmarks[ei][3] == col
			then
				new_id = data.extmarks[ei][1]
				ei = ei + 1
			end
			vim.api.nvim_buf_set_extmark(data.buf, data.ns_id, line_nr, col, {
				id = new_id,
				virt_text = { { (' '):rep(delta), M.opts.highlight } },
				virt_text_pos = 'inline',
				right_gravity = true,
				scoped = true,
			})
		end
	end
	while data.extmarks[ei] ~= nil do
		vim.api.nvim_buf_del_extmark(data.buf, data.ns_id, data.extmarks[ei][1])
		ei = ei + 1
	end
end
local function align_win(data)
	-- FIXME: when one window is heavily wrapped with long alignments strange things happen
	-- TODO: cleanup unsued namespaces
	local win_ns = vim.api.nvim_win_add_ns or vim.api.nvim__win_add_ns
	if win_ns == nil then return end -- NOTE: API change
	data.ns_id = vim.api.nvim_create_namespace(('align-win-%d'):format(data.window))
	win_ns(data.window, data.ns_id)
	data.extmarks = vim.api.nvim_buf_get_extmarks(data.buf, data.ns_id,
		{ data.state.start - 2 + data.min_i, 0 },
		{ data.state.start - 2 + data.max_i, -1 },
		{ type = 'virt_text', details = true })
	convert_indicies_to_columns_of_alignments(data)
	figure_out_sections(data)
	align_sections(data)
	apply_alignment(data)
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
	-- `table` of `modes` (output of `nvim_get_mode().mode`).
	-- Leave empty if you want to always update the alignments.
	update_in_modes = {}, -- `array` of mode short-names (`n`, `i`, ...)
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
