{
  programs = {
    aerospace = {
      enable = true;
      userSettings = {
        start-at-login = true;
        accordion-padding = 30;
        mode.main.binding = {
          alt-enter = ''
            exec-and-forget osascript -e '
            tell application "Kitty"
                do script
                activate
            end tell'
          '';
          alt-tab = "workspace-back-and-forth";
        };
        gaps = {
          outer.left = 8;
          outer.bottom = 8;
          outer.top = 8;
          outer.right = 8;
        };
        on-focus-changed = [
          "move-mouse monitor-lazy-center"
        ];
        on-focused-monitor-changed = [
          "move-mouse monitor-lazy-center"
        ];
      };
    };
  };
}
