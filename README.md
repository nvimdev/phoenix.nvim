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

**Require neovim nightly**

```lua
require('phoenix').setup()
```

default config and custom in `vim.g.phoenix` option table.

```
{
  filetypes = { '*' },
  -- Dictionary related settings
  dict = {
    -- Maximum number of words to store in the dictionary
    -- Higher values consume more memory but provide better completions
    max_words = 50000,

    -- Minimum word length to be considered for completion
    -- Shorter words may create noise in completions
    min_word_length = 2,
    -- Time factor weight for sorting completions (0-1)
    -- Higher values favor recently used items more strongly
    recency_weight = 0.3,

    -- Base weight for frequency in sorting (0-1)
    -- Complements recency_weight, should sum to 1
    frequency_weight = 0.7,
  },

  -- Performance related settings
  scan = {
    cache_ttl = 5000,
    -- Number of items to process in each batch
    -- Higher values improve speed but may cause stuttering
    batch_size = 1000,
    -- Ignored the file or dictionary which matched the pattern
    ignore_patterns = {},

    -- Throttle delay for dictionary updates in milliseconds
    -- Prevents excessive CPU usage during rapid file changes
    throttle_ms = 100,
  },
}
```

## License MIT
