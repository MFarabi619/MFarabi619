{
  pkgs,
  ...
}:
{
  environment = {
    systemPackages = with pkgs; [
      # menubar-cli
      macmon
      # yabai
      # skhd
      kanata        # keyboard layering
      coreutils
      alt-tab-macos # alt-tab on mac
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
