local wezterm = require 'wezterm'
local act = wezterm.action

local function field(t, color, text)
  if #t > 0 then
    table.insert(t, { Foreground = { AnsiColor = 'Grey' } })
    table.insert(t, { Text = ' | ' })
  end
  table.insert(t, { Foreground = { AnsiColor = color } })
  table.insert(t, { Text = text })
end

wezterm.on('update-status', function(window, pane)
  local items = {}
  local kt = window:active_key_table() or 'NORM'
  field(items, kt == 'NORM' and 'Grey' or 'Yellow', kt)

  local is_zoomed = false
  local tab = window:active_tab()
  if tab then
    for _, pane_info in ipairs(tab:panes_with_info()) do
      if pane_info.is_active then
        is_zoomed = pane_info.is_zoomed
        break
      end
    end
  end

  field(items, is_zoomed and 'Lime' or 'Grey', 'ZOOM')
  table.insert(items, { Text = '  '})

  window:set_left_status(wezterm.format({
    { Foreground = { AnsiColor = 'Grey' } },
    { Text = 'ws: ' },
    { Foreground = { AnsiColor = 'Silver' } },
    { Text = window:active_workspace() },
  }))
  window:set_right_status(wezterm.format(items))
end)

local config = {
  prefer_egl = true,
  font = wezterm.font 'Sarasa Mono SC',
  font_size = 14,
  color_scheme = 'Bespin (base16)',
  default_cursor_style = 'BlinkingBar',
  audible_bell = 'Disabled',
  window_decorations = 'RESIZE',
  window_padding = { left = '1px', right = '1px', top = '1px', bottom = '1px' },
  ssh_domains = wezterm.default_ssh_domains(),
  launch_menu = {
    { label = 'PowerShell', args = { 'powershell.exe', '-NoLogo' } },
    { label = 'CMD', args = { 'cmd.exe' } },
    { label = 'TermSCP', args = { 'termscp.exe' } },
  },
  keys = {
    { key = 'Tab', mods = 'CTRL', action = act.ActivateLastTab },
    { key = 'Space', mods = 'ALT', action = act.ActivateKeyTable {
      name = 'CTRL',
      replace_current = false,
      one_shot = false,
    }},
  },
  key_tables = {
    CTRL = {
      { key = 'Space', mods = 'ALT', action = act.Multiple {
        act.ActivatePaneDirection 'Next',
        act.ClearKeyTableStack,
      }},
      { key = '[', action = act.ActivateTabRelativeNoWrap(-1) },
      { key = ']', action = act.ActivateTabRelativeNoWrap(1) },
      { key = '{', mods = 'SHIFT', action = act.MoveTabRelative(-1) },
      { key = '}', mods = 'SHIFT', action = act.MoveTabRelative(1) },
      { key = '-', action = act.Multiple { act.SplitPane { direction = 'Down' }, act.ClearKeyTableStack }},
      { key = '_', mods = 'SHIFT', action = act.Multiple { act.SplitPane { direction = 'Up' }, act.ClearKeyTableStack }},
      { key = '\\', action = act.Multiple { act.SplitPane { direction = 'Right' }, act.ClearKeyTableStack }},
      { key = '|', mods = 'SHIFT', action = act.Multiple { act.SplitPane { direction = 'Left' }, act.ClearKeyTableStack }},
      { key = 'h', action = act.ActivatePaneDirection 'Left' },
      { key = 'j', action = act.ActivatePaneDirection 'Down' },
      { key = 'k', action = act.ActivatePaneDirection 'Up' },
      { key = 'l', action = act.ActivatePaneDirection 'Right' },
      { key = 'h', mods = 'SHIFT', action = act.AdjustPaneSize { 'Left', 1 }},
      { key = 'j', mods = 'SHIFT', action = act.AdjustPaneSize { 'Down', 1 }},
      { key = 'k', mods = 'SHIFT', action = act.AdjustPaneSize { 'Up', 1 }},
      { key = 'l', mods = 'SHIFT', action = act.AdjustPaneSize { 'Right', 1 }},
      { key = 't', action = act.Multiple { act.SpawnTab 'CurrentPaneDomain', act.ClearKeyTableStack }},
      { key = 'Return', action = act.Multiple { act.TogglePaneZoomState, act.ClearKeyTableStack }},
      { key = 'Escape', action = act.ClearKeyTableStack },
    }
  },
}

return config
