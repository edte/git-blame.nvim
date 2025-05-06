local M = {}

function M.show()
  local info, err = M.commit_info()

  if err then
    vim.notify(err, vim.log.levels.ERROR, {
      title = string.format("Messenger.nvim"),
    })
    return
  end

  local content = M.format_content(info)
  M.create_window(content)
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

  if info.commit_hash == nil then
    info.commit_msg = "Not Committed Yet"
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
  local msg_lines = vim.split(info.commit_msg, "\n")
  local content = {}

  if info.commit_hash then
    info.commit_hash = string.sub(info.commit_hash, 1, 8)
    table.insert(content, string.format("Commit: %s", info.commit_hash))
  end
  if info.author then
    table.insert(content, string.format("Author: %s <%s>", info.author, info.author_email))
  end
  if info.date then
    table.insert(content, string.format("Date:   %s", info.date))
  end

  -- Append commit message lines
  for _, line in ipairs(msg_lines) do
    table.insert(content, vim.trim(line))
  end

  -- Remove last line if it is only whitespace
  local last_line = content[#content]

  if last_line:match("^%s*$") then
    table.remove(content)
  end

  return content
end

function M.locate_gitdir()
  local current_dir = vim.fn.getcwd()
  local git_dir = vim.fn.finddir(".git", current_dir .. ";")
  return git_dir ~= "" and vim.fn.fnamemodify(git_dir, ":p:h:h") or nil
end

function M.create_window(content)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, content)

  -- Define highlighting groups for colors

  vim.cmd("highlight MessengerHeadings guifg=" .. "#89b4fa")

  vim.api.nvim_buf_add_highlight(buf, -1, "MessengerHeadings", 0, 0, 7)
  vim.api.nvim_buf_add_highlight(buf, -1, "MessengerHeadings", 1, 0, 7)
  vim.api.nvim_buf_add_highlight(buf, -1, "MessengerHeadings", 2, 0, 5)

  -- Adjust height and width based on content
  local width = 0
  for _, line in ipairs(content) do
    if #line > width then
      width = #line
    end
  end
  local height = #content

  local win_config = {
    relative = "cursor",
    style = "minimal",
    width = width + 2,
    height = height,
    row = 1,
    col = 1,
    border = "single",
  }

  local win_id = vim.api.nvim_open_win(buf, false, win_config)

  vim.wo[win_id].foldenable = false
  vim.wo[win_id].wrap = false
  vim.wo[win_id].list = false

  local win_hl = "FloatBorder:MessengerBorder,FloatTitle:MessengerTitle"
  vim.wo[win_id].winhighlight = win_hl

  local augroup = vim.api.nvim_create_augroup("MessengerWindow" .. win_id, { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
    group = augroup,
    callback = function()
      vim.api.nvim_win_close(win_id, true)
      vim.api.nvim_del_augroup_by_id(augroup)
    end,
    once = true,
  })
end

return M
