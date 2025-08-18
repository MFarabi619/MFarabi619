{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      # menubar-cli
      yabai
      skhd
      macmon
    ];

    pathsToLink = [
      "/share/zsh"
      "/share/bash-completion"
    ];
  };
}
