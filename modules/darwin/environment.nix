{
  pkgs,
  ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      macmon             # mac monitoring TUI
      coreutils
      # menubar-cli
      alt-tab-macos      # alt-tab on mac
      # kanata-with-cmd    # keyboard layering
    ];

    systemPath = [
      "/usr/local/bin"
      "/opt/homebrew/bin"
      "/Users/mfarabi/.local/bin"
      "/Users/mfarabi/.cargo/bin"
      # "/Users/mfarabi/.bun/bin"
      "/Users/mfarabi/Library/pnpm"
      # "/Users/mfarabi/.lmstudio/bin"
    ];

    pathsToLink = [
      "/share/zsh"
      "/Applications"
      "/share/bash-completion"
    ];
  };
}
