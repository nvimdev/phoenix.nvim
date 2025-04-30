local client_capabilities = {}
local projects = {}

---Default configuration values for Phoenix
---@type PhoenixConfig
local default = {
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
    priority = {
      base = 100, -- Base priority score (0-999)
      position = 'after', -- Position relative to other LSP results: 'before' or 'after'
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
    enable_notify = false, -- Enable notify when cleanup dictionary
  },

  -- Scanner settings control filesystem interaction
  scanner = {
    scan_batch_size = 1000, -- Scan 1000 items per batch
    cache_duration_ms = 5000, -- Cache results for 5s
    throttle_delay_ms = 200, -- Wait 200ms between updates
    ignore_patterns = {}, -- No ignore patterns by default
  },
  snippet = '',
}

--@type PhoenixConfig
local Config = setmetatable({}, {
  __index = function(_, scope)
    if vim.g.phoenix and vim.g.phoenix[scope] ~= nil then
      return vim.g.phoenix[scope]
    end
    return default[scope]
  end,
})

local Trie = {}
function Trie.new()
  return {
    children = {},
    is_end = false,
    frequency = 0,
    last_used = 0, -- timestamp for LRU-based cleanup
  }
end

function Trie.insert(root, word, timestamp)
  local node = root
  local path = {} -- record node in path

  for i = 1, #word do
    local char = word:sub(i, i)
    node.children[char] = node.children[char] or Trie.new()
    node = node.children[char]
    table.insert(path, node)
  end

  local was_new = not node.is_end
  node.is_end = true
  node.frequency = node.frequency + 1
  node.last_used = timestamp
  return was_new
end

function Trie.search_prefix(root, prefix)
  local node = root
  for i = 1, #prefix do
    local char = prefix:sub(i, i)
    if not node.children[char] then
      return {}
    end
    node = node.children[char]
  end
  local count = 0

  local results = {}
  local function collect_words(current_node, current_word)
    if current_node.is_end then
      count = count + 1
      table.insert(results, {
        word = current_word,
        frequency = current_node.frequency,
        last_used = current_node.last_used,
      })
    end

    for char, child in pairs(current_node.children) do
      collect_words(child, current_word .. char)
      if count >= Config.completion.max_items then
        break
      end
    end
  end

  collect_words(node, prefix)
  return results
end

local dict = {
  trie = Trie.new(),
  word_count = 0,
  max_words = Config.dict.capacity,
  min_word_length = Config.dict.min_word_length,
}

-- LRU cache
local LRUCache = {}

-- Node constructor
local function new_node(key, value)
  return { key = key, value = value, prev = nil, next = nil }
end

function LRUCache:new(max_size)
  local obj = {
    cache = {},
    head = nil,
    tail = nil,
    max_size = max_size or 100,
    size = 0,
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

-- Move node to the head of the list
function LRUCache:move_to_head(node)
  if node == self.head then
    return
  end
  self:remove(node)
  self:add_to_head(node)
end

-- Add node to the head of the list
function LRUCache:add_to_head(node)
  node.next = self.head
  node.prev = nil
  if self.head then
    self.head.prev = node
  end
  self.head = node
  if not self.tail then
    self.tail = node
  end
  self.size = self.size + 1
end

-- Remove node from the list
function LRUCache:remove(node)
  if node.prev then
    node.prev.next = node.next
  else
    self.head = node.next
  end
  if node.next then
    node.next.prev = node.prev
  else
    self.tail = node.prev
  end
  self.size = self.size - 1
end

-- Remove the tail node
function LRUCache:remove_tail()
  if not self.tail then
    return nil
  end
  local tail_node = self.tail
  self:remove(tail_node)
  return tail_node
end

-- Get the value of a key
function LRUCache:get(key)
  local node = self.cache[key]
  if not node then
    return nil
  end
  self:move_to_head(node)
  return node.value
end

-- Put a key-value pair into the cache
function LRUCache:put(key, value)
  local node = self.cache[key]
  if node then
    node.value = value
    self:move_to_head(node)
  else
    if self.size >= self.max_size then
      local tail_node = self:remove_tail()
      if tail_node then
        self.cache[tail_node.key] = nil
      end
    end
    local newNode = new_node(key, value)
    self:add_to_head(newNode)
    self.cache[key] = newNode
  end
end

local scan_cache = LRUCache:new(100)

local server = {}

local function schedule_result(callback, items)
  vim.schedule(function()
    callback(nil, { isIncomplete = false, items = items or {} })
  end)
end

local function scan_dir_async(path, callback)
  local cached = scan_cache:get(path)
  if cached and (vim.uv.now() - cached.timestamp) < Config.scanner.cache_duration_ms then
    callback(cached.results)
    return
  end

  local co = coroutine.create(function(resolve)
    local handle = vim.uv.fs_scandir(path)
    if not handle then
      resolve({})
      return
    end

    local results = {}
    local batch_size = Config.scanner.scan_batch_size
    local current_batch = {}

    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        if #current_batch > 0 then
          vim.list_extend(results, current_batch)
        end
        break
      end

      if #Config.scanner.ignore_patterns > 0 then
        local ok = vim.iter(Config.scanner.ignore_patterns):any(function(pattern)
          return name:match(pattern)
        end)
        if ok then
          goto continue
        end
      end

      local is_hidden = name:match('^%.')
      if type == 'directory' and not name:match('/$') then
        name = name .. '/'
      end

      table.insert(current_batch, {
        name = name,
        type = type,
        is_hidden = is_hidden,
      })

      if #current_batch >= batch_size then
        vim.list_extend(results, current_batch)
        current_batch = {}
        coroutine.yield()
      end
      ::continue::
    end

    scan_cache:put(path, {
      timestamp = vim.uv.now(),
      results = results,
    })
    resolve(results)
  end)

  local function handle_error(err)
    vim.schedule(function()
      vim.notify(string.format('Error in scan_dir_async: %s', err), vim.log.levels.ERROR)
      callback({})
    end)
  end

  local ok, err = coroutine.resume(co, callback)
  if not ok then
    handle_error(err)
  end
end

-- async cleanup low frequency from dict
local function cleanup_dict()
  local cleanup_Config = Config.cleanup
  local cmp_Config = Config.completion

  -- Only cleanup if dictionary is getting full
  if dict.word_count <= Config.dict.capacity * cleanup_Config.cleanup_ratio then
    return
  end

  -- Create cleanup timer
  local timer = assert(vim.uv.new_timer())
  timer:start(cleanup_Config.idle_timeout_ms, 0, function()
    timer:stop()
    timer:close()

    local co = coroutine.create(function()
      local words = {}
      local max_frequency = 0

      -- Collect words and find max frequency
      local function collect_words(node, current_word)
        if node.is_end then
          max_frequency = math.max(max_frequency, node.frequency)
          table.insert(words, {
            word = current_word,
            frequency = node.frequency,
            last_used = node.last_used,
          })
        end

        -- Yield after processing collection_batch_size words
        if #words % cleanup_Config.collection_batch_size == 0 then
          coroutine.yield()
        end

        for char, child in pairs(node.children) do
          collect_words(child, current_word .. char)
        end
      end

      -- Start collecting words
      collect_words(dict.trie, '')
      coroutine.yield()

      -- Sort by combined score (frequency and recency)
      table.sort(words, function(a, b)
        -- Calculate scores using configured weights
        local a_score = (a.frequency / max_frequency) * cmp_Config.weights.frequency
          + (a.last_used / vim.uv.now()) * cmp_Config.weights.recency
        local b_score = (b.frequency / max_frequency) * cmp_Config.weights.frequency
          + (b.last_used / vim.uv.now()) * cmp_Config.weights.recency
        return a_score > b_score
      end)

      -- Filter out low frequency words
      local threshold = max_frequency * cleanup_Config.frequency_threshold
      local filtered_words = {}
      for _, word in ipairs(words) do
        if word.frequency >= threshold then
          table.insert(filtered_words, word)
        end
        if #filtered_words >= Config.dict.capacity then
          break
        end
      end
      coroutine.yield()

      -- Rebuild trie with remaining words
      local new_trie = Trie.new()
      local new_count = 0

      -- Process words in batches
      for i = 1, #filtered_words, cleanup_Config.cleanup_batch_size do
        local batch_end = math.min(i + cleanup_Config.cleanup_batch_size - 1, #filtered_words)

        -- Process current batch
        for j = i, batch_end do
          local word_data = filtered_words[j]
          Trie.insert(new_trie, word_data.word, word_data.last_used)
          new_count = new_count + 1
        end

        -- Yield after each batch
        if i % cleanup_Config.rebuild_batch_size == 0 then
          coroutine.yield()
        end
      end

      -- Update dictionary with cleaned data
      dict.trie = new_trie
      dict.word_count = new_count

      if cleanup_Config.enable_notify then
        vim.notify(
          string.format('Dictionary cleaned: reduced from %d to %d words', #words, new_count),
          vim.log.levels.INFO
        )
      end
    end)

    -- Handle coroutine execution
    local function resume()
      local ok, err = coroutine.resume(co)
      if not ok then
        vim.notify(string.format('Error in cleanup_dict: %s', err), vim.log.levels.ERROR)
        return
      end

      if coroutine.status(co) ~= 'dead' then
        vim.schedule(resume)
      end
    end

    vim.schedule(resume)
  end)
end

local function visible_range(content)
  local top = vim.fn.line('w0')
  local bot = vim.fn.line('w$')
  return vim.iter(vim.split(content, '\n')):slice(top, bot):join('\n')
end

-- Core word processing function
local function process_words(line, seen, dict_config)
  local new_words = 0
  local now = vim.uv.now()

  for word in line:gmatch(dict_config.word_pattern) do
    if not seen[word] and #word >= dict_config.min_word_length then
      if Trie.insert(dict.trie, word, now) then
        new_words = new_words + 1
        seen[word] = true
      end
    end
  end

  return new_words
end

-- Batch processing function
local function process_lines_batch(lines, start_idx, batch_size, seen, dict_config)
  local end_idx = math.min(start_idx + batch_size, #lines)
  local new_words = 0

  for i = start_idx + 1, end_idx do
    new_words = new_words + process_words(lines[i], seen, dict_config)
  end

  dict.word_count = dict.word_count + new_words
  return end_idx
end

local async = require('phoenix.async')

-- Initialize dictionary with full content
local initialize_dict = async.throttle(function(lines)
  local dict_config = Config.dict
  local scanner_config = Config.scanner
  local processed = 0
  local seen = {}

  local function process_batch()
    processed =
      process_lines_batch(lines, processed, scanner_config.scan_batch_size, seen, dict_config)

    if processed < #lines then
      vim.schedule(process_batch)
    elseif dict.word_count > dict_config.capacity then
      cleanup_dict()
    end
  end

  vim.schedule(process_batch)
end, Config.scanner.throttle_delay_ms)

local Snippet = {
  cache = {},
  loading = {},
}

function Snippet:preload()
  local ft = vim.bo.filetype
  if self.cache[ft] or self.loading[ft] then
    return
  end
  local path = vim.fs.joinpath(Config.snippet, ('%s.json'):format(ft))
  if vim.fn.filereadable(path) == 1 then
    self.loading[ft] = true
    async.read_file(path, function(data)
      local success, snippets = pcall(vim.json.decode, data)
      if success then
        self.cache[ft] = snippets
        self.loading[ft] = nil
      else
        vim.notify(
          string.format('Error parsing snippet file for %s: %s', ft, snippets),
          vim.log.levels.ERROR
        )
        self.cache[ft] = {}
        self.loading[ft] = nil
      end
    end)
  end
end

local function parse_snippet(input)
  local ok, parsed = pcall(function()
    return vim.lsp._snippet_grammar.parse(input)
  end)
  return ok and tostring(parsed) or input
end

function Snippet:get_completions(prefix)
  local ft = vim.bo.filetype
  local results = {}

  if not self.cache[ft] then
    return results
  end

  local snippets = self.cache[ft]
  for trigger, snippet_data in pairs(snippets) do
    if vim.startswith(trigger:lower(), prefix:lower()) then
      local body = snippet_data.body
      local insert_text = body

      if type(body) == 'table' then
        insert_text = table.concat(body, '\n')
      end

      table.insert(results, {
        label = trigger,
        kind = 15,
        insertText = insert_text,
        documentation = {
          kind = 'markdown',
          value = (snippet_data.description and snippet_data.description .. '\n\n' or '')
            .. '```'
            .. ft
            .. '\n'
            .. parse_snippet(insert_text)
            .. '\n```',
        },
        detail = 'Snippet: ' .. (snippet_data.description or ''),
        sortText = string.format('001%s', trigger),
        insertTextFormat = 2,
      })
    end
  end

  table.sort(results, function(a, b)
    return a.label < b.label
  end)

  return results
end

local function collect_completions(prefix)
  local results = Trie.search_prefix(dict.trie, prefix)
  local now = vim.uv.now()
  local decay_time = Config.completion.decay_minutes * 60 * 1000
  local priority_config = Config.completion.priority

  local max_freq = 0
  for _, result in ipairs(results) do
    max_freq = math.max(max_freq, result.frequency)
    result.time_factor = math.max(0, 1 - (now - result.last_used) / decay_time)
  end

  table.sort(results, function(a, b)
    local score_a = (a.frequency / max_freq * Config.completion.weights.frequency)
      + (a.time_factor * Config.completion.weights.recency)
    local score_b = (b.frequency / max_freq * Config.completion.weights.frequency)
      + (b.time_factor * Config.completion.weights.recency)
    return score_a > score_b
  end)

  -- Calculate sort prefix based on priority configuration
  local sort_prefix = priority_config.position == 'before'
      and string.format('%03d', priority_config.base)
    or string.format('%03d', priority_config.base + 100)

  local special_lists = { 'c', 'cpp' }

  return vim
    .iter(ipairs(results))
    :map(function(idx, node)
      return {
        label = vim.list_contains(special_lists, vim.bo.filetype) and ' ' .. node.word or node.word,
        filterText = node.word,
        kind = 1,
        sortText = string.format('%s%09d%s', sort_prefix, idx, node.word),
      }
    end)
    :totable()
end

local function find_last_occurrence(str, patterns)
  local reversed_str = string.reverse(str)
  for _, pattern in ipairs(patterns) do
    local start_pos, end_pos = string.find(reversed_str, pattern)
    if start_pos then
      return #str - end_pos + 1
    end
  end
  return nil
end

-- LSP handler functions
local function handle_document_open(params)
  local text = params.textDocument.text
  if #text == 0 then
    return
  end
  local content = vim.split(text, '%s', { trimempty = true })
  if #content == 0 then
    return
  end

  initialize_dict(content)
end

local function handle_document_change(params)
  if tonumber(vim.fn.pumvisible()) == 1 then
    return
  end

  -- Process only the changed text
  local change = params.contentChanges[1]
  if not change or not change.text then
    return
  end

  -- Process just the changed text
  local lines = vim.split(change.text, '\n')
  if #lines == 0 then
    return
  end

  -- Process the new text directly without comparing to old version
  local seen = {}
  local dict_config = Config.dict
  local new_words = 0

  for _, line in ipairs(lines) do
    new_words = new_words + process_words(line, seen, dict_config)
  end

  dict.word_count = dict.word_count + new_words

  if dict.word_count > dict.max_words then
    cleanup_dict()
  end
end

function server.create()
  return function()
    local srv = {}

    function srv.initialize(params, callback)
      local client_id = params.processId
      if params.rootPath and not projects[params.rootPath] then
        projects[params.rootPath] = {}
      end
      client_capabilities[client_id] = params.capabilities
      callback(nil, {
        capabilities = {
          completionProvider = {
            triggerCharacters = { '/' },
            resolveProvider = false,
          },
          textDocumentSync = {
            openClose = true,
            change = 1,
          },
        },
      })
    end

    function srv.completion(params, callback)
      local position = params.position
      -- local lines = vim.split(root[filename], '\n')
      local line = vim.api.nvim_get_current_line()
      if #line == 0 then
        schedule_result(callback)
        return
      end

      local char_at_cursor = line:sub(position.character, position.character)
      if char_at_cursor == '/' then
        local prefix = line:sub(1, position.character)
        local has_literal = find_last_occurrence(prefix, { '"', "'" })
        if has_literal then
          prefix = prefix:sub(has_literal + 1, position.character)
        end
        local has_space = find_last_occurrence(prefix, { '%s' })
        if has_space then
          prefix = prefix:sub(has_space + 1, position.character)
        end
        local dir_part = prefix:match('^(.*/)[^/]*$')

        if not dir_part then
          schedule_result(callback)
          return
        end

        local expanded_path = vim.fn.has('nvim-0.10') and vim.fn.expand(dir_part)
          or vim.fs.normalize(vim.fs.abspath(dir_part))

        scan_dir_async(expanded_path, function(results)
          local items = {}
          local current_input = prefix:match('[^/]*$') or ''

          for _, entry in ipairs(results) do
            local name = entry.name
            if vim.startswith(name:lower(), current_input:lower()) then
              local kind = entry.type == 'directory' and 19 or 17
              local label = name
              local ishidden = false
              if entry.type == 'directory' then
                label = label:gsub('/$', '')
              elseif entry.type == 'file' and name:match('^%.') then
                ishidden = true
              end

              table.insert(items, {
                label = label,
                kind = kind,
                insertText = label,
                filterText = ishidden and label:gsub('^.', '') or label,
                detail = entry.is_hidden and '(Hidden)' or nil,
                sortText = string.format('%d%s', entry.is_hidden and 1 or 0, label:lower()),
              })
            end
          end

          schedule_result(callback, items)
        end)
      else
        local prefix = line:sub(1, position.character):match('[%w_]*$')
        if not prefix or #prefix == 0 then
          schedule_result(callback)
          return
        end

        local items = collect_completions(prefix)
        local snippets = Snippet:get_completions(prefix)
        schedule_result(callback, vim.list_extend(items, snippets))
      end
    end

    srv['textDocument/completion'] = srv.completion

    srv['textDocument/didOpen'] = handle_document_open
    srv['textDocument/didChange'] = handle_document_change

    srv['textDocument/didClose'] = function(params) end

    function srv.shutdown(params, callback)
      callback(nil, nil)
    end

    return {
      request = function(method, params, callback)
        if srv[method] then
          srv[method](params, callback)
        else
          callback({ message = 'Method not found: ' .. method })
        end
      end,
      notify = function(method, params)
        if srv[method] then
          srv[method](params)
        end
      end,
      is_closing = function()
        return false
      end,
      terminate = function()
        client_capabilities = {}
      end,
    }
  end
end

return {
  register = function()
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('Phoenix', { clear = true }),
      pattern = Config.filetypes,
      callback = function(args)
        if vim.bo[args.buf].filetype == '' or vim.bo[args.buf].buftype == 'nofile' then
          return
        end

        vim.lsp.start({
          name = 'phoenix',
          cmd = server.create(),
          root_dir = vim.uv.cwd(),
          reuse_client = function()
            return true
          end,
        })

        if #Config.snippet > 0 then
          Snippet:preload()
        end
      end,
      desc = 'Phoenix autostart',
    })
  end,
}
