{
  # https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
  services.yabai = {
    enable = true;
    enableScriptingAddition = true;
    config = {
      layout = "bsp"; # bsp(default) | stack | float
      # New window spawns to the right if vertical split, bottom if horizontal split
      window_placement = "second_child";
      window_shadow = "on";
      window_opacity = "on";
      active_window_opacity = 1.0;
      normal_window_opacity = 0.80;
      insert_feedback_color = "0xff3e8fb0";
      window_opacity_duration = 0.15;
      window_animation_duration = 0.22;

      top_padding = 5;
      bottom_padding = 5;
      left_padding = 5;
      right_padding = 5;
      window_gap = 5;

      auto_balance = "on";
      # split_ratio = 0.5;

      menubar_opacity = 0.75;
      # external_bar = "all:36:0";

      mouse_follows_focus = "on";
      focus_follows_mouse = "autoraise";

      mouse_modifier = "cmd"; # modifier for clicking and dragging with mouse
      mouse_action1 = "move"; # mod + left-click drag to move window
      mouse_action2 = "resize"; # mod + right-click drag to resize window
      # when window is dropped in center of another window, swap them (on edges it will split it)
      mouse_drop_action = "swap";
    };
    extraConfig = ''
      yabai -m rule --add app="^System Settings$" manage=off
      yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
      sudo yabai --load-sa
    '';
  };
}
