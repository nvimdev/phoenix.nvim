if vim.g.loaded_phoenix then
  return
end

vim.g.loaded_phoenix = true
require('phoenix').register()
