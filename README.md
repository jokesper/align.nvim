# align.nvim
A simple plugin to allow alignment over multiple lines.

## [Elastic Tabstops](https://nick-gravgaard.com/elastic-tabstops/)
[Elastic Tabstops](https://nick-gravgaard.com/elastic-tabstops/) can be emulated
with `\t` in the `align` field. This is set by default.
The width of the alignment does not follow the specs (minimum width)

## Requirements
- nvim >= 0.10.x

## Installation

### [lazy.nvim](https://github.com/wbthomason/packer.nvim)
```lua
{ 'jokesper/align.nvim' }
```

## Configuration
Configuration happens in lua.
If you would like to instead configure it using vimscript,
see `:help lua-heredoc`.

### Default configuration
```lua
require 'align'.setup {
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
	-- 4. A `table` representing multiple patterns with optional properties.
	-- 	  The properties can be:
	-- 	  - `align` which specifies how to align the pattern.
	-- 	    One of `left`, `right` or `center`.
	align = {
		[0] = {
			'\t',
			{ '%s[+-]?[%d.,]+', align = 'right' },
		},
		['*'] = {
			[0] = {
				' = ',
			},
		},
		csv = {
			[0] = {
				',',
			},
		},
	},
}
```
