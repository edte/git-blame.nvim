local M = {}

function M.show()
  local info, err = M.commit_info()

  if err then
    vim.notify(err, vim.log.levels.ERROR, {
      title = string.format("Messenger.nvim"),
    })
    return
  end

  local content, length = M.format_content(info)
  M.create_window(content, length)
end

function M.commit_info()
  local gitdir = M.locate_gitdir()
  if not gitdir then
    return nil, "Not a git repository"
  end

  local info, err = M.blame_info(gitdir)
  if err then
    return nil, err
  end

  if info.commit_hash == nil or info.commit_hash == "0000000000000000000000000000000000000000" then
    info.commit_hash = nil
    return info
  end

  local message, err = M.commit_message(gitdir, info.commit_hash)

  if err then
    return nil, err
  end

  info.commit_msg = message

  return info
end

function M.blame_info(gitdir) -- ${func, blame_info}
  local file_path = vim.fn.expand("%:p")
  local line_num = vim.api.nvim_win_get_cursor(0)[1]

  -- Get the blame information for the current line
  local blame_cmd = string.format("git -C %s blame -L %d,%d --porcelain %s", gitdir, line_num, line_num, file_path)
  local blame_output = vim.fn.system(blame_cmd)

  if vim.v.shell_error ~= 0 then
    local info = {}
    return vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info)
  end

  -- Parse the blame output
  local commit_hash = blame_output:match("^(%x+)")
  if not commit_hash then
    local info = {}
    return vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info)
  end

  local author = blame_output:match("author%s+([^\n]+)")
  if not author then
    local info = {}
    return vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info)
  end

  local author_email = blame_output:match("author%-mail%s+<([^>]+)>")
  if not author_email then
    local info = {}
    return vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info)
  end

  local author_time = blame_output:match("author%-time (%d+)")
  if not author_time then
    local info = {}
    return vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info)
  end

  -- Convert author_time to a readable format
  local date = os.date("%F %H:%M", tonumber(author_time))
  if not date then
    local info = {}
    return vim.tbl_map(function(v)
      return type(v) == "string" and vim.trim(v) or v
    end, info)
  end

  local info = {
    author = author,
    author_email = author_email,
    commit_hash = commit_hash,
    date = date,
  }

  -- Trim all string values in the table
  return vim.tbl_map(function(v)
    return type(v) == "string" and vim.trim(v) or v
  end, info)
end

function M.commit_message(gitdir, commit_hash) -- ${func, commit_message}
  local message_cmd = string.format("git -C %s show -s --format=%%B %s", gitdir, commit_hash)
  local message = vim.fn.system(message_cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Error getting commit message: " .. message
  end

  return message
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
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, content)

  vim.api.nvim_buf_add_highlight(buf, -1, "@label", 0, 0, length.commitAndNameEnd)
  vim.api.nvim_buf_add_highlight(buf, -1, "NvimOptionScope", 0, length.TimeBegin, -1)

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

  local win_hl = "FloatBorder:@label"
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
