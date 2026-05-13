-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

-- Environment variables --
require("hyprland/env")
require("custom/env")

-- Defaults --
require("hyprland/execs")
require("hyprland/general")
require("hyprland/rules")
require("hyprland/colors")
require("hyprland/keybinds")

-- Custom --
require("custom/execs")
require("custom/monitors")
require("custom/general")
require("custom/rules")
require("custom/keybinds")

-- Shell overrides --
require("hyprland/shellOverrides/main")
