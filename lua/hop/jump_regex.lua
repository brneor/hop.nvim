---@class Regex
---@field oneshot boolean
---@field linewise boolean Determines if regex considers whole lines
---@field match fun(s:string, jctx:JumpContext, opts:Options):ColumnRange Get column range within the line string

---@class JumpRegexModule
local M = {}

local hint = require('hop.hint')
local window = require('hop.window')
local mappings = require('hop.mappings')

-- JumpRegex modes for the buffer-driven generator.
---@param s string
---@return boolean
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  -- if it’s a space, we assume it’s not uppercase, even though Lua doesn’t agree with us; I mean, Lua is horrible, who
  -- would like to argue with that creature, right?
  if f == ' ' then
    return false
  end

  return f:upper() == f
end

-- JumpRegex by searching a pattern.
---@param pat string
---@param plain_search boolean|nil
---@return Regex
local function regex_by_searching(pat, plain_search)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Wrapper over M.regex_by_searching to add support for case sensitivity.
---@param pat string
---@param plain_search boolean
---@param opts Options
---@return Regex
function M.regex_by_case_searching(pat, plain_search, opts)
  local pat_case = ''
  if vim.o.smartcase then
    if not starts_with_uppercase(pat) then
      pat_case = '\\c'
    end
  elseif opts.case_insensitive then
    pat_case = '\\c'
  end
  local pat_mappings = mappings.checkout(pat, opts)

  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  if pat_mappings ~= '' then
    pat = string.format([[\(%s\)\|\(%s\)]], pat, pat_mappings)
  end
  pat = pat .. pat_case

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Word regex.
---@return Regex
function M.regex_by_word_start()
  return regex_by_searching('\\k\\+')
end

-- Camel case regex.
---@return Regex
function M.regex_by_camel_case()
  local camel = '\\u\\l\\+'
  local acronyms = '\\u\\+\\ze\\u\\l'
  local upper = '\\u\\+'
  local lower = '\\l\\+'
  local rgb = '#\\x\\+\\>'
  local ox = '\\<0[xX]\\x\\+\\>'
  local oo = '\\<0[oO][0-7]\\+\\>'
  local ob = '\\<0[bB][01]\\+\\>'
  local num = '\\d\\+'

  local tab = { camel, acronyms, upper, lower, rgb, ox, oo, ob, num, '\\~', '!', '@', '#', '$' }
  -- regex that matches camel or acronyms or upper ... or num ...
  local patStr = '\\%(\\%(' .. table.concat(tab, '\\)\\|\\%(') .. '\\)\\)'

  local pat = vim.regex(patStr)
  return {
    oneshot = false,
    match = function(s)
      return pat:match_str(s)
    end,
  }
end

-- Line regex.
---@return Regex
function M.by_line_start()
  return {
    oneshot = true,
    linewise = true,
    match = function()
      return 0, 1
    end,
  }
end

-- Line regex at cursor position.
---@return Regex
function M.regex_by_vertical()
  return {
    oneshot = true,
    linewise = true,
    ---@param s string
    ---@param jctx JumpContext
    match = function(s, jctx)
      if jctx.direction == hint.HintDirection.AFTER_CURSOR then
        return 0, 1
      end
      local idx = window.cell2char(s, jctx.win_ctx.col_first)
      local col = vim.fn.byteidx(s, idx)
      if -1 < col and col < #s then
        return col, col + 1
      else
        return #s - 1, #s
      end
    end,
  }
end

-- Line regex skipping finding the first non-whitespace character on each line.
---@return Regex
function M.regex_by_line_start_skip_whitespace()
  local regex = vim.regex('\\S')

  return {
    oneshot = true,
    linewise = true,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Anywhere regex.
---@return Regex
function M.regex_by_anywhere()
  return regex_by_searching('\\v(<.|^$)|(.>|^$)|(\\l)\\zs(\\u)|(_\\zs.)|(#\\zs.)')
end

return M