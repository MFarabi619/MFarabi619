{
  services.aerospace = {
   enable = true;

    settings = { # yoinked from github.com/ryangchung/ryangchung/blob/main/modules/home/programs/aerospace.nix
      after-startup-command = [
        "layout tiles"
      ];

      default-root-container-layout = "tiles"; # tiles | accordion
      # Possible values: horizontal|vertical|auto
      # 'auto' means: wide monitor (anything wider than high) gets horizontal orientation,
      #               tall monitor (anything higher than wide) gets vertical orientation
      default-root-container-orientation = "auto";
      automatically-unhide-macos-hidden-apps = false;
      # nikitabobko.github.io/AeroSpace/guide#normalization
      enable-normalization-flatten-containers = true;
      enable-normalization-opposite-orientation-for-nested-containers = true;

      gaps = {
        inner = {
          vertical = 10;
          horizontal = 10;
        };

        outer = {
          top = 10;
          left = 8;
          right = 8;
          bottom = 8;
        };
      };

        exec-on-workspace-change = [
          "/bin/bash"
          "-c"
          "sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE PREV_WORKSPACE=$AEROSPACE_PREV_WORKSPACE"
        ];


      mode.main.binding = {
        alt-tab = "workspace-back-and-forth";

        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";

        alt-h = "move left";
        alt-j = "move down";
        alt-k = "move up";
        alt-l = "move right";

        # alt-h = "focus left";
        # alt-j = "focus down";
        # alt-k = "focus up";
        # alt-l = "focus right";

        # cmd-ctrl-shift-h = "move left";
        # cmd-ctrl-shift-j = "move down";
        # cmd-ctrl-shift-k = "move up";
        # cmd-ctrl--shift-l = "move right";

        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

        alt-enter = "fullscreen";
        cmd-enter = "macos-native-fullscreen";

        cmd-1 = "workspace 1";
        cmd-2 = "workspace 2";
        cmd-3 = "workspace 3";
        cmd-4 = "workspace 4";
        cmd-5 = "workspace 5";
        cmd-6 = "workspace 6";
        cmd-7 = "workspace 7";
        cmd-8 = "workspace 8";
        cmd-9 = "workspace 9";
        cmd-0 = "workspace 10";

        cmd-alt-1 = "move-node-to-workspace 1";
        cmd-alt-2 = "move-node-to-workspace 2";
        cmd-alt-3 = "move-node-to-workspace 3";
        cmd-alt-4 = "move-node-to-workspace 4";
        cmd-alt-5 = "move-node-to-workspace 5";
        cmd-alt-6 = "move-node-to-workspace 6";
        cmd-alt-7 = "move-node-to-workspace 7";
        cmd-alt-8 = "move-node-to-workspace 8";
        cmd-alt-9 = "move-node-to-workspace 9";
        cmd-alt-0 = "move-node-to-workspace 10";

        cmd-alt-tab = "move-workspace-to-monitor --wrap-around next";

        alt-shift-semicolon = "mode service";

        # See: https://nikitabobko.github.io/AeroSpace/commands#move-node-to-workspace
        # --focus-follows-window is used to ensure workspace changes to trigger the callback for sketchybar to update
        alt-shift-1 = "move-node-to-workspace 1 --focus-follows-window";
        alt-shift-2 = "move-node-to-workspace 2 --focus-follows-window";
        alt-shift-3 = "move-node-to-workspace 3 --focus-follows-window";
        alt-shift-4 = "move-node-to-workspace 4 --focus-follows-window";
        alt-shift-5 = "move-node-to-workspace 5 --focus-follows-window";
        alt-shift-6 = "move-node-to-workspace 6 --focus-follows-window";
        alt-shift-7 = "move-node-to-workspace 7 --focus-follows-window";
        alt-shift-8 = "move-node-to-workspace 8 --focus-follows-window";
        alt-shift-9 = "move-node-to-workspace 9 --focus-follows-window";
        alt-shift-a = "move-node-to-workspace A --focus-follows-window";
        alt-shift-b = "move-node-to-workspace B --focus-follows-window";
        alt-shift-c = "move-node-to-workspace C --focus-follows-window";
        alt-shift-d = "move-node-to-workspace D --focus-follows-window";
        alt-shift-e = "move-node-to-workspace E --focus-follows-window";
        #alt-shift-f = "move-node-to-workspace F' # disabled as it's a common code formatting hotkey"
        alt-shift-g = "move-node-to-workspace G --focus-follows-window";
        alt-shift-i = "move-node-to-workspace I --focus-follows-window";
        alt-shift-m = "move-node-to-workspace M --focus-follows-window";
        alt-shift-n = "move-node-to-workspace N --focus-follows-window";
        alt-shift-o = "move-node-to-workspace O --focus-follows-window";
        alt-shift-p = "move-node-to-workspace P --focus-follows-window";
        alt-shift-q = "move-node-to-workspace Q --focus-follows-window";
        alt-shift-r = "move-node-to-workspace R --focus-follows-window";
        alt-shift-s = "move-node-to-workspace S --focus-follows-window";
        alt-shift-t = "move-node-to-workspace T --focus-follows-window";
        alt-shift-u = "move-node-to-workspace U --focus-follows-window";
        alt-shift-v = "move-node-to-workspace V --focus-follows-window";
        alt-shift-w = "move-node-to-workspace W --focus-follows-window";
        alt-shift-x = "move-node-to-workspace X --focus-follows-window";
        alt-shift-y = "move-node-to-workspace Y --focus-follows-window";
        alt-shift-z = "move-node-to-workspace Z --focus-follows-window";
      };

      "workspace-to-monitor-force-assignment" = {
          "1" = "main";
          "2" = "main";
          "3" = "main";
          "4" = "main";
          "5" = "main";
          "6" = "main";
          "7" = "main";
          "8" = "main";
          "9" = "main";
          "10" = "secondary";
      };
    };
  };
}
