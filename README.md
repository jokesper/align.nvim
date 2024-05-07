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
	-- `table` of `modes` (output of `nvim_get_mode().mode`).
	-- Leave empty if you want to always update the alignments.
	update_in_modes = {}, -- `array` of mode short-names (`n`, `i`, ...)
	align = { ' = ', '\t' }, -- `table` of patterns to align.
}
```
