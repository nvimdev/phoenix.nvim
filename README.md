# Phoenix

A blazing-fast in-process server providing word (based on frequency score and) path completion.

## How fast it is ?

It enables smooth word completion in nearly 10,000 lines of text and provides
instant completion in projects with thousands of files.

![Image](https://github.com/user-attachments/assets/ec81041b-7f37-4613-ad91-419a76ee2eeb)

[Completion Config](#completion)

In the Phoenix, a Trie tree is used to store words, ensuring that the
completion results can be obtained in O(L) time (L is the length of the word).
Additionally, the weight of each word is calculated based on its usage frequency
and last usage time, and low-frequency words are asynchronously cleaned up periodically
to ensure that the desired results can be obtained quickly with each input.

For path completion, Phoenix uses an LRU (Least Recently Used) cache to handle
the results, and the completion results can be obtained in O(1) time. Meanwhile,
the cache is cleaned up based on a set time period to ensure that the directory
status is kept synchronized.

## Usage

Install with any plugin manager or builtin `:help packages`.
Phoenix can work with any completion plugin which support lsp source or neovim
nightly `vim.lsp.completion` module.

## Config

Used `vim.g.phoenix` option table and modified the field what you need before
plugin loaded.

```lua
---Default configuration values for Phoenix
---@type PhoenixConfig
vim.g.phoenix = {
  -- Enable for all filetypes by default
  filetypes = { '*' },

  -- Dictionary settings control word storage
  dict = {
    capacity = 50000, -- Store up to 50k words
    min_word_length = 2, -- Ignore single-letter words
    word_pattern = '[^%s%.%_:%p%d]+', -- Word pattern
  },

  -- Completion control the scoring
  completion = {
    max_items = 1000, -- Max result items
    decay_minutes = 30, -- Time period for decay calculation
    weights = {
      recency = 0.3, -- 30% weight to recent usage
      frequency = 0.7, -- 70% weight to frequency
    },
    priority = 500,
  },

  -- Cleanup settings control dictionary maintenance
  cleanup = {
    cleanup_batch_size = 1000, -- Process 1000 words per batch
    frequency_threshold = 0.1, -- Keep words used >10% of max frequency
    collection_batch_size = 100, -- Collect 100 words before yielding
    rebuild_batch_size = 100, -- Rebuild 100 words before yielding
    idle_timeout_ms = 1000, -- Wait 1s before cleanup
    cleanup_ratio = 0.9, -- Cleanup at 90% capacity
    enable_notify = false, -- Enable notify when cleanup dictionary
  },

  -- Scanner settings control filesystem interaction
  scanner = {
    scan_batch_size = 1000, -- Scan 1000 items per batch
    cache_duration_ms = 5000, -- Cache results for 5s
    throttle_delay_ms = 200, -- Wait 200ms between updates
    ignore_patterns = {}, -- Dictionary or file ignored when path completion
  },
  snippet = '' -- path of snippet json file like c.json/zig.json/go.json
}
```

## Completion

1. Phoenix should works with any completion plugin which support lsp source.

2. I have a simple wrapper around `vim.lsp.completion` for works on character which
   does not exist in server triggerCharacters since `vim.lsp.completion` used
   `InsertcharPre` for autotrigger. Notice this script does not works when
   deleted a character if you want need use `TextChangedI`.

```lua
vim.opt.cot = 'menu,menuone,noinsert,fuzzy,popup'
vim.opt.cia = 'kind,abbr,menu'

api.nvim_create_autocmd('LspAttach', {
  group = g,
  callback = function(args)
    local bufnr = args.buf
    local client = lsp.get_client_by_id(args.data.client_id)
    if not client or not client:supports_method(ms.textDocument_completion) then
      return
    end
    local chars = client.server_capabilities.completionProvider.triggerCharacters
    if chars then
      for i = string.byte('a'), string.byte('z') do
        if not vim.list_contains(chars, string.char(i)) then
          table.insert(chars, string.char(i))
        end
      end
    end

    completion.enable(true, client.id, bufnr, {
      autotrigger = true,
      convert = function(item)
        return {
          abbr = item.label:gsub('%b()', ''),
          kind = item.kind:gsub('^.', string.lower)
        }
      end,
    })
  end,
})
```

## License MIT
