# nvim-gbrain-explorer

Browse and edit [GBrain](https://github.com/garrytan/gbrain) pages from Neovim.

The plugin opens recent pages or server-side search results in Telescope. The
same commands use a plain buffer when Telescope is unavailable. Pages open as
normal Markdown buffers and save to GBrain with `:write`.

## Requirements

- Neovim 0.10 or newer
- curl 8.3 or newer
- GBrain MCP endpoint
- `GBRAIN_REMOTE_TOKEN` in Neovim's environment
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), optional

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "cosgroveb/nvim-gbrain-explorer",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  cmd = {
    "GBrainExplorer",
    "GBrainSearch",
    "GBrainCreate",
  },
  keys = {
    {
      "<leader>gbe",
      "<cmd>GBrainExplorer<cr>",
      desc = "Browse GBrain pages",
    },
    {
      "<leader>gbs",
      "<cmd>GBrainSearch<cr>",
      desc = "Search GBrain pages",
    },
  },
  opts = {
    endpoint = "https://gbrain.example.com/mcp",
  },
}
```

Remove `dependencies` to use the built-in buffer interface without Telescope.
This plugin installs beside `nvim-atuin-kv-explorer`; it does not replace or
configure it.

## Use

| Command | Action |
| --- | --- |
| `:GBrainExplorer` | Browse up to 100 recently updated pages |
| `:GBrainSearch [query]` | Search GBrain; prompt when query is omitted |
| `:GBrainCreate [slug]` | Open a new page; prompt when slug is omitted |

Telescope mappings:

| Mapping | Action |
| --- | --- |
| `<CR>` | Open selected page |
| `<C-r>` | Refresh current results |
| `<C-n>` | Create page |
| `<C-d>` | Confirm and soft-delete selected page |

Buffer-interface mappings:

| Mapping | Action |
| --- | --- |
| `<CR>` | Open selected page |
| `r` | Refresh current results |
| `c` | Create page |
| `d` | Confirm and soft-delete selected page |
| `q` | Close explorer |

Pages open in `gbrain://` buffers. Edit them normally and run `:write` to call
GBrain's `put_page`. Failed writes leave the buffer modified. GBrain
soft-deletes pages for 72 hours.

Recent browsing follows GBrain's 100-page server limit. Use
`:GBrainSearch` to find older pages.

Result rows put the title first. Telescope can fuzzy-match the title, type, or
slug.

## Configure

Set `endpoint` to the full URL of the GBrain MCP endpoint:

```lua
require("gbrain-explorer").setup({
  endpoint = "https://gbrain.example.com/mcp",
  token_env = "GBRAIN_REMOTE_TOKEN",
  ui_mode = "auto", -- "auto", "telescope", or "buffer"
  timeout_ms = 10000,
  page_limit = 100,
  search_limit = 50,
})
```

`endpoint` is required. The other values shown above are defaults. lazy.nvim
calls `setup()` with `opts`; other plugin managers must call it directly.

## Design

UI code depends on a page client with five operations: list, search, get, put,
and delete. A separate transport owns curl, authentication, MCP
initialization, JSON-RPC, and JSON/SSE responses. Telescope remains optional,
and neither UI knows how GBrain is transported.

## Develop

Install [StyLua](https://github.com/JohnnyMorganz/StyLua) and
[Luacheck](https://github.com/lunarmodules/luacheck), then run:

```sh
make format
make lint
make test
make check
```

Tests run headless with fake client and transport boundaries. They do not write
to GBrain.

## License

[MIT](LICENSE)
