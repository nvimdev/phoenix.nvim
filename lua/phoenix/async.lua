local uv = vim.uv

local function wrap_async(func)
  return function(...)
    local args = { ... }
    return function(callback)
      table.insert(args, callback)
      func(unpack(args))
    end
  end
end

local async_fs_open = wrap_async(uv.fs_open)
local async_fs_fstat = wrap_async(uv.fs_fstat)
local async_fs_read = wrap_async(uv.fs_read)
local async_fs_close = wrap_async(uv.fs_close)

local function await(promise)
  local co = coroutine.running()
  promise(function(...)
    local args = { ... }
    vim.schedule(function()
      assert(coroutine.resume(co, unpack(args)))
    end)
  end)
  return coroutine.yield()
end

local function async(func)
  return function(...)
    local co = coroutine.create(func)
    local function step(...)
      local ok, err = coroutine.resume(co, ...)
      if not ok then
        error(err)
      end
    end
    step(...)
  end
end

local read_file = async(function(filepath, callback)
  local err, fd = await(async_fs_open(filepath, 'r', 438))
  assert(not err, err)

  local err, stat = await(async_fs_fstat(fd))
  assert(not err, err)

  local err, data = await(async_fs_read(fd, stat.size, 0))
  await(async_fs_close(fd))
  assert(not err, err)
  callback(data)
end)

function throttle(fn, delay)
  local timer = nil
  return function(...)
    local args = { ... }
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    timer = assert(vim.uv.new_timer())
    timer:start(
      delay,
      0,
      vim.schedule_wrap(function()
        if timer and not timer:is_closing() then
          timer:stop()
          timer:close()
          fn(unpack(args))
        end
      end)
    )
  end
end

return {
  read_file = read_file,
  throttle = throttle,
}
