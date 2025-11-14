# NOTE: ensure to disable SIP (System Integrity Protection) first
# developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection#Disable-System-Integrity-Protection-Temporarily

# 1. reboot and press on boot screen CMD+R
# 2. open boot terminal and `csrutil disable`
# 3. reboot
# 4. profit

{
  pkgs,
  ...
}:
{
  services.yabai = {
    enable = pkgs.stdenv.isx86_64;


    enableScriptingAddition = true;

    config = {
      layout = "bsp"; # bsp(default) | stack | float
      # New window spawns to the right if vertical split, bottom if horizontal split
      window_shadow = "on";
      window_opacity = "on";
      active_window_opacity = 1.0;
      normal_window_opacity = 0.98;
      window_opacity_duration = 0.15;
      window_animation_duration = 0.22;
      window_placement = "second_child";
      insert_feedback_color = "0xff3e8fb0";

      window_gap = 0;
      top_padding = 0;
      left_padding = 0;
      right_padding = 0;
      bottom_padding = 0;

      auto_balance = "on";
      # split_ratio = 0.5;

      menubar_opacity = 0;
      external_bar = "all:52:0";

      mouse_follows_focus = "off";
      focus_follows_mouse = "autoraise";

      mouse_modifier = "cmd"; # modifier for clicking and dragging with mouse
      mouse_action1 = "move"; # mod + left-click drag to move window
      mouse_action2 = "resize"; # mod + right-click drag to resize window
      # when window is dropped in center of another window, swap them (on edges it will split it)
      mouse_drop_action = "swap";
    };

    extraConfig = ''
      yabai -m rule --add app="^System Settings$" manage=off
      yabai -m rule --add app="^System Preferences" manage=off
      yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
      sudo yabai --load-sa
    '';
  };
}
