-- Murmo web-app panel.
--
-- The Murmo Secure Messenger web app is launched by
-- ~/.config/omarchy/plugins/pinta365.murmo/bin/murmo-panel, which also toggles
-- the special workspace "murmo". Chromium ignores --class for --app windows and
-- derives the Wayland app_id as "chrome-<url-host>__-<profile-directory>", so
-- the launcher names the profile directory "murmo-panel" and the window arrives
-- as e.g. "chrome-murmo.org__-murmo-panel". Match that, park it on the special
-- workspace hidden by default, and float it as a top-right panel under the bar.
o.window("^chrome-.*__-murmo-panel$", {
  workspace = "special:murmo silent",
  float = true,
  size = { 460, 720 },
  -- monitor_w-476 keeps a 16px gap on the right of a 460px-wide panel; 42 sits
  -- below the 26px bar reservation plus the same gap.
  move = { "(monitor_w-476)", "42" },
  center = false,
})
