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

all config in `vim.g.phoenix` option table see source file ...

## License MIT
