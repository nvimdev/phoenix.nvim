# Phoenix

A blazing-fast asynchronous in-process server providing word and path completion.

## How fast it is ?

It enables smooth word completion in nearly 10,000 lines of text and provides
instant completion in projects with thousands of files.

![Image](https://github.com/user-attachments/assets/ec81041b-7f37-4613-ad91-419a76ee2eeb)

([auto completion from my neovim config](https://github.com/glepnir/nvim/blob/main/lua/internal/completion.lua))

In the Phoenix framework, a Trie tree is used to store words, ensuring that the
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

```lua
require('phoenix').setup()
```

Phoenix can work with any completion plugin which support lsp source or neovim
nightly `vim.lsp.completion` module.

## Config

default config and custom in `vim.g.phoenix` option table.

```
---Default configuration values for Phoenix
{
  -- Enable for all filetypes by default
  filetypes = { '*' },

  -- Dictionary settings control word storage and scoring
  dict = {
    capacity = 50000, -- Store up to 50k words
    min_word_length = 2, -- Ignore single-letter words
    weights = {
      recency = 0.3, -- 30% weight to recent usage
      frequency = 0.7, -- 70% weight to frequency
    },
  },

  -- Cleanup settings control dictionary maintenance
  cleanup = {
    cleanup_batch_size = 1000, -- Process 1000 words per batch
    frequency_threshold = 0.1, -- Keep words used >10% of max frequency
    collection_batch_size = 100, -- Collect 100 words before yielding
    rebuild_batch_size = 100, -- Rebuild 100 words before yielding
    idle_timeout_ms = 1000, -- Wait 1s before cleanup
    cleanup_ratio = 0.9, -- Cleanup at 90% capacity
  },

  -- Scanner settings control filesystem interaction
  scanner = {
    scan_batch_size = 1000, -- Scan 1000 items per batch
    cache_duration_ms = 5000, -- Cache results for 5s
    throttle_delay_ms = 100, -- Wait 100ms between updates
    ignore_patterns = {}, -- No ignore patterns by default
  },
}
```

## License MIT
