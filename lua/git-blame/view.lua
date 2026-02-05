local M = {}
M._message_cache = M._message_cache or {}
M._hl_defined = M._hl_defined or false

function M.show()
  M.commit_info_async(function(info, err)
    vim.schedule(function()
      if err then
        vim.notify(err, vim.log.levels.ERROR, {
          title = string.format("Messenger.nvim"),
        })
        return
      end

      local content, length = M.format_content(info)
      M.create_window(content, length)
    end)
  end)
end

function M.commit_info_async(cb)
  local gitdir = M.locate_gitdir()
  if not gitdir then
    cb(nil, "Not a git repository")
    return
  end

  M.blame_info_async(gitdir, function(info, err)
    if err then
      cb(nil, err)
      return
    end

    if info.commit_hash == nil or info.commit_hash == "0000000000000000000000000000000000000000" then
      info.commit_hash = nil
      cb(info)
      return
    end

    local cached = M._message_cache[info.commit_hash]
    if cached then
      info.commit_msg = cached
      cb(info)
      return
    end

    M.commit_message_async(gitdir, info.commit_hash, function(message, msg_err)
      if msg_err then
        cb(nil, msg_err)
        return
      end
      M._message_cache[info.commit_hash] = message
      info.commit_msg = message
      cb(info)
    end)
  end)
end

function M.run_git(args, cb)
  if vim.system then
    vim.system(args, { text = true }, function(obj)
      if obj.code ~= 0 then
        local msg = (obj.stderr and obj.stderr ~= "" and obj.stderr) or obj.stdout or "git error"
        cb(nil, vim.trim(msg))
      else
        cb(obj.stdout, nil)
      end
    end)
    return
  end

  local output = {}
  local errors = {}
  local job_id = vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(errors, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      local out = table.concat(output, "\n")
      local err = table.concat(errors, "\n")
      if code ~= 0 then
        cb(nil, vim.trim(err ~= "" and err or out))
      else
        cb(out, nil)
      end
    end,
  })

  if job_id <= 0 then
    cb(nil, "Failed to start git process")
  end
end

function M.blame_info_async(gitdir, cb) -- ${func, blame_info}
  local file_path = vim.fn.expand("%:p")
  local line_num = vim.api.nvim_win_get_cursor(0)[1]

  local blame_args = {
    "git",
    "-C",
    gitdir,
    "blame",
    "-L",
    string.format("%d,%d", line_num, line_num),
    "--porcelain",
    "--",
    file_path,
  }

  M.run_git(blame_args, function(blame_output, err)
    if err then
      cb(nil, "Error getting blame: " .. err)
      return
    end

    -- Parse the blame output
    local commit_hash = blame_output:match("^(%x+)")
    if not commit_hash then
      cb(nil, "Error parsing blame output")
      return
    end

    local author = blame_output:match("author%s+([^\n]+)")
    if not author then
      cb(nil, "Error parsing blame author")
      return
    end

    local author_email = blame_output:match("author%-mail%s+<([^>]+)>")
    if not author_email then
      cb(nil, "Error parsing blame author email")
      return
    end

    local author_time = blame_output:match("author%-time (%d+)")
    if not author_time then
      cb(nil, "Error parsing blame author time")
      return
    end

    -- Convert author_time to a readable format
    local date = os.date("%F %H:%M", tonumber(author_time))
    if not date then
      cb(nil, "Error parsing blame date")
      return
    end

    local info = {
      author = author,
      author_email = author_email,
      commit_hash = commit_hash,
      date = date,
    }

    cb(vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info))
  end)
end

function M.commit_message_async(gitdir, commit_hash, cb) -- ${func, commit_message}
  local message_args = {
    "git",
    "-C",
    gitdir,
    "show",
    "-s",
    "--format=%B",
    commit_hash,
  }

  M.run_git(message_args, function(message, err)
    if err then
      cb(nil, "Error getting commit message: " .. err)
      return
    end

    cb(message)
  end)
end

function M.format_content(info)
  if not info.commit_hash then
    local content = {}
    local t = "Not Committed Yet"
    table.insert(content, t)
    local length = {
      commitAndNameEnd = 0,
      TimeBegin = 0,
      MessageLength = M.getLen(t),
    }
    return content, length
  end

  local msg_lines = vim.split(info.commit_msg, "\n")
  local content = {}

  local length = {
    commitAndNameEnd = 9 + M.getLen(info.author),
    TimeBegin = 10 + M.getLen(info.author),
    MessageLength = 0,
  }

  if info.commit_hash then
    info.commit_hash = string.sub(info.commit_hash, 1, 8)
    local s = string.format("%s %s (%s):", info.commit_hash, info.author, info.date)
    table.insert(content, s)

    length.MessageLength = math.max(length.MessageLength, M.getLen(s))
  end

  local need = true

  for _, line in ipairs(msg_lines) do
    local t = vim.trim(line)

    if need then
      if t ~= "" then
        table.insert(content, t)
        need = false

        length.MessageLength = math.max(length.MessageLength, M.getLen(t))
      end
    end
  end

  return content, length
end

function M.locate_gitdir()
  local current_dir = vim.fn.getcwd()
  local git_dir = vim.fn.finddir(".git", current_dir .. ";")
  return git_dir ~= "" and vim.fn.fnamemodify(git_dir, ":p:h:h") or nil
end

function M.create_window(content, length)
  if not M._hl_defined then
    vim.api.nvim_set_hl(0, "MessengerLabel", { fg = "#82aaff" })
    vim.api.nvim_set_hl(0, "MessengerTime", { fg = "#c099ff" })
    vim.api.nvim_set_hl(0, "MessengerBorder", { fg = "#82aaff" })
    M._hl_defined = true
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, content)

  vim.api.nvim_buf_add_highlight(buf, -1, "MessengerLabel", 0, 0, length.commitAndNameEnd)
  vim.api.nvim_buf_add_highlight(buf, -1, "MessengerTime", 0, length.TimeBegin, -1)

  -- Adjust height and width based on content
  local width = 0
  for _, line in ipairs(content) do
    if #line > width then
      width = #line
    end
  end

  local height = 2

  if length.TimeBegin == 0 and length.commitAndNameEnd == 0 then
    height = 1
  end

  local win_config = {
    relative = "cursor",
    style = "minimal",
    width = length.MessageLength + 1,
    height = height,
    row = 1,
    col = 1,
    border = "single",
  }

  local win_id = vim.api.nvim_open_win(buf, false, win_config)

  vim.wo[win_id].foldenable = false
  vim.wo[win_id].wrap = false
  vim.wo[win_id].list = false

  local win_hl = "FloatBorder:MessengerBorder"
  vim.wo[win_id].winhighlight = win_hl

  local augroup = vim.api.nvim_create_augroup("MessengerWindow" .. win_id, { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
    group = augroup,
    callback = function()
      if vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
      end
      vim.api.nvim_del_augroup_by_id(augroup)
    end,
    once = true,
  })
end

function M.getLen(s)
  return vim.fn.strdisplaywidth(s)
end

return M
