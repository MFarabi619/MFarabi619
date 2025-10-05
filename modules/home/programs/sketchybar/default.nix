{
  lib,
  pkgs,
  ...
}:
{
  programs.sketchybar = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    # configType = "lua";
    # luaPackage = pkgs.lua5_4;
    # sbarLuaPackage = pkgs.sbarlua;
    service.enable = true;
    includeSystemPath = true;
    extraPackages = with pkgs; [
      jq
    ];

    # config = {
    #   source = ./sketchybar;
    #   recursive = true;
    # };

    # config = ''
    # -- init.lua — SketchyBar config (Lua)

    # local COLOR_BLACK = "0xff181926"
    # local COLOR_WHITE = "0xffcad3f5"
    # local COLOR_GRAY  = "0xff363a4f"
    # local COLOR_BLUE  = "0xff8aadf4"
    # local COLOR_GREEN = "0xffa6da95"
    # local COLOR_YELLOW= "0xffeed49f"
    # local COLOR_RED   = "0xffed8796"

    # local WIFI_IFACE = "en0"

    # local function sh(cmd)
    #   -- print(cmd) -- uncomment to debug the emitted commands
    #   os.execute(cmd)
    # end

    # sh(string.format(
    #   'sketchybar --bar height=32 position=top topmost=on padding_left=10 padding_right=10 color=%s corner_radius=8 shadow=on',
    #   COLOR_BLACK
    # ))

    # sh(string.format([[
    # sketchybar --default \
    #   icon.font="SF Pro:Bold:14.0" \
    #   icon.color=%s \
    #   label.font="SF Pro:Bold:14.0" \
    #   label.color=%s \
    #   background.padding_left=5 \
    #   background.padding_right=5
    # ]], COLOR_WHITE, COLOR_WHITE))

    # -- Apple logo (click to open System Settings)
    # sh(string.format([[
    # sketchybar --add item apple left \
    #   --set apple icon="" icon.color=%s \
    #   click_script="open -a 'System Settings'"
    # ]], COLOR_RED))

    # -- Space indicator (requires yabai + jq)
    # sh([[
    # sketchybar --add item space_indicator left \
    #   --set space_indicator \
    #     script="yabai -m query --spaces --display | jq -r '.[] | select(.focused==1).label'" \
    #     update_freq=5 \
    #     icon=🖥
    # ]])

    # sh([[
    # sketchybar --add item front_app center \
    #   --set front_app \
    #     script="osascript -e 'tell application \"System Events\" to get name of (first application process whose frontmost is true)'" \
    #     update_freq=5
    # ]])

    # sh([[
    # sketchybar --add item clock right \
    #   --set clock \
    #     script="date '+%H:%M'" \
    #     update_freq=10 \
    #     icon="🕒"
    # ]])

    # sh([[
    # sketchybar --add item battery right \
    #   --set battery \
    #     script="pmset -g batt | grep -Eo '[0-9]+%%' | head -1" \
    #     update_freq=30 \
    #     icon="🔋"
    # ]])

    # sh([[
    # sketchybar --add item volume right \
    #   --set volume \
    #     script="osascript -e 'output volume of (get volume settings)'" \
    #     update_freq=10 \
    #     icon="🔊"
    # ]])

    # sh(string.format([[
    # sketchybar --add item wifi right \
    #   --set wifi \
    #     script="/usr/sbin/networksetup -getairportnetwork %s | sed 's/^Current Wi-Fi Network: //'" \
    #     update_freq=30 \
    #     icon="📶"
    # ]], WIFI_IFACE))

    # sh("sketchybar --update")
    # '';
  };

  home.file = {
    ".config/sketchybar" = {
        enable = true;
        source = ./sketchybar;
        recursive = true;
    };

    # "config/sketchybar/.luarc.json" = {
    #   enable = true;
    #   text = ''
    #     {
    #         "diagnostics.globals": [
    #             "vim",
    #             "icons",
    #             "colors",
    #             "bar",
    #             "default",
    #             "helpers"
    #         ],
    #         "runtime.version": "Lua 5.4"
    #     }
    #     '';
    # };

    # ".config/sketchybar/sketchybarrc" = {
    #     enable = false;
    #     text = ''
    #     #!/usr/bin/env lua

    #     -- Load the sketchybar-package and prepare the helper binaries
    #     require("helpers")
    #     require("init")
    #     '';
    # };
  };
}
