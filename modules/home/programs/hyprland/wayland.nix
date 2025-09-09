{ lib, pkgs, ... }:
{
  wayland.windowManager.hyprland = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    package = null;
    xwayland = {
      enable = true;
    };
    systemd = {
      enable = true;
      enableXdgAutostart = true;
      variables = [
        "--all"
      ];
      extraCommands = [
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
        "dbus-update-activation-environment --systemd --all"
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
        "$term --hold fastfetch"
        "vivaldi"
        "emacs -nw"
      ];
    };

    extraConfig = "
        monitor=Virtual-1,4096x2160@165,auto,3.2
        windowrule = nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0
     ";

    settings = {
      monitor = ",1920x1080@144,auto,1.6";
      xwayland.force_zero_scaling = true;

      env = [
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "QT_QPA_PLATFORM,wayland;xcb"
        "QT_QPA_PLATFORMTHEME,qt6ct"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "QT_AUTO_SCREEN_SCALE_FACTOR,1"
        "MOZ_ENABLE_WAYLAND,1"
        "GDK_SCALE,2"
      ];

      "$mainMod" = "SUPER";
      "$editor" = "nvim";
      "$file" = "dolphin";
      "$term" = "kitty";
      "$browser" = "vivaldi";
      "$menu" = "rofi -show drun";

      # exec-once = [
      # ];

      bind = [
        # Apps
        "$mainMod, T, exec, $term"
        "$mainMod, E, exec, $file"
        "$mainMod, C, exec, $editor"
        "$mainMod, F, exec, $browser"

        # Switch workspaces to a relative workspace
        "$mainMod, L, workspace, r+1"
        "$mainMod, H, workspace, r-1"

        # Window/Session
        "$mainMod, W, togglefloating" # toggle focus/float
        "$mainMod, G, togglegroup" # toggle focus/group
        "Alt, Return, fullscreen" # toggle focus/fullscreen
        "Ctrl+Alt, W, exec, killall waybar || waybar"
        "$mainMod,Q,killactive,"
        # Move focused window around the current workspace
        "$mainMod+Shift+Ctrl, H, movewindow, l"
        "$mainMod+Shift+Ctrl, L, movewindow, r"
        "$mainMod+Shift+Ctrl, K, movewindow, u"
        "$mainMod+Shift+Ctrl, J, movewindow, d"
        # Move focused window to relative workspace
        "$mainMod+Alt, L, movetoworkspace, r+1"
        "$mainMod+Alt, H, movetoworkspace, r-1"
        # Move/Change window focus
        "$mainMod, Left, movefocus, l"
        "$mainMod, Right, movefocus, r"
        "$mainMod, Up, movefocus, u"
        "$mainMod, Down, movefocus, d"
        "ALT,Tab,cyclenext"
        "ALT,Tab,bringactivetotop"

        ",XF86MonBrightnessDown,exec,brightnessctl set 5%-"
        ",XF86MonBrightnessUp,exec,brightnessctl set +5%"

        # Show keybind hints
        "$mainMod, code:61, exec, pkill -x rofi || rofi -show keys"

        # Rofi menus
        "$mainMod, A, exec, pkill -x rofi || $menu" # launch application launcher
        "$mainMod, R, exec, pkill -x rofi || rofi -show run" # launch program launcher
      ]
      ++ (
        # Switch workspaces
        builtins.concatLists (
          builtins.genList (
            i:
            let
              ws = i + 1;
            in
            [
              "$mainMod, code:1${toString i}, workspace, ${toString ws}"
              "$mainMod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
            ]
          ) 9
        )
      );

      bindm = [
        # Move/resize windows with mainMod + LMB/RMB and dragging
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
        "$mainMod, Z, movewindow"
        "$mainMod, X, resizewindow"
      ];

      animations = {
        enabled = false;
      };

      decoration = {
        rounding = 10;
        rounding_power = 2;

        active_opacity = 0.9;
        inactive_opacity = 0.7;

        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          # color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;
          size = 4;
          passes = 2;
          new_optimizations = true;
          vibrancy = 0.1696;
          ignore_opacity = true;
          xray = false;
        };
      };

      dwindle = {
        preserve_split = true;
        pseudotile = true;
      };

      master = {
        new_status = "master";
      };

      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;
        layout = "dwindle";
        allow_tearing = false;
        resize_on_border = true;
      };

      gestures = {
        workspace_swipe = true;
        workspace_swipe_fingers = 3;
        workspace_swipe_forever = true;
        workspace_swipe_invert = false;
      };

      input = {
        kb_layout = "us";
        kb_options = "ctrl:nocaps";

        touchpad = {
          natural_scroll = true;
        };

        follow_mouse = 1;
      };

      misc = {
        enable_swallow = false;
        vfr = true; # Variable Frame Rate
        vrr = 2; # Variable Refresh Rate  Might need to set to 0 for NVIDIA/AQ_DRM_DEVICES
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        force_default_wallpaper = 0;
      };

      render = {
        direct_scanout = 0;
      };
    };
  };
}
