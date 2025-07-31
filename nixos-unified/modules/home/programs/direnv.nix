{ config, pkgs, ... }:
{
  # https://nixos.asia/en/direnv
  programs.direnv = {
    enable = true;
    silent = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv = {
      enable = true;
    };
    config.global = {
      # Make direnv messages less verbose
      # hide_env_diff = true;
    };
  };
}
