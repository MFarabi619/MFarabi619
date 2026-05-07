{
  config,
  ...
}:
{
  programs.nix-your-shell = {
    enable = true;
    nix-output-monitor.enable = true;
    enableZshIntegration = config.programs.zsh.enable;
  };
}
