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
				and data.extmarks[ei][3] < alignment.align do
				for _, text in ipairs(data.extmarks[ei][4].virt_text) do
					-- NOTE: text should only contain spaces
					shifted = shifted + #text[1]
				end
				ei = ei + 1
			end
			local align = vim.fn.virtcol { data.state.start - 1 + i, alignment.align }
			align = align - shifted
			converted[i][j] = {
				col = alignment.col,
				align = align,
				key = alignment.key,
			}
		end
	end
	data.lines = converted
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

---@param data {lines: {[number]: {col: number, align: number, key: string, aligned: {align: number, deps: {[table]: boolean}}?}, progress: number?}[], min_i: number, max_i: number}
local function figure_out_sections(data)
	local function normalize_line(i)
		data.lines[i] = vim.tbl_filter(function(alignment) return alignment.aligned ~= nil end, data.lines[i])
		for j = 2, #data.lines[i] do data.lines[i][j].aligned.deps[data.lines[i][j - 1].aligned] = true end
		data.lines[i].progress = 1
	end
	for i = data.min_i, data.max_i - 1 do
		local current, next = data.lines[i], data.lines[i + 1]
		for _, alignment in ipairs(lcs(current, next, 'key')) do
			local j, k = alignment[1], alignment[2]
			local aligned = current[j].aligned or { align = 0, deps = {} }
			current[j].aligned = aligned
			next[k].aligned = aligned
		end
		normalize_line(i)
	end
	normalize_line(data.max_i)
end

---@param data {lines: {[number]: {col: number, align: number, key: string, aligned: {align: number, deps: {[table]: boolean}}}, progress: number}[]}
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
			local shift = last ~= nil and (last.aligned.align - last.align) or 0
			current.aligned.align = math.max(current.aligned.align, current.align + shift)
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
			local col = alignment.col - 1
			local delta = alignment.aligned.align - alignment.align - shift
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
				virt_text = { { (' '):rep(delta), 'Alignment' } },
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

return function(data)
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
	-- TODO:
	-- move prior te per window alignment, for earlier cut-off
	-- (we can cut of when there is nothing in common instead of when there is nothing).
	figure_out_sections(data)
	align_sections(data)
	apply_alignment(data)
end
