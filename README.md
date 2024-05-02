# align.nvim
A simple plugin to allow alignment over multiple lines.

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
	align = { ' = ', ', ', '{', '}', '%[', '%]', '%(', '%)' }, -- `table` of patterns to align.
}
```
