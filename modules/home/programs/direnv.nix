{
  home.shellAliases.da = "direnv allow";
  programs.direnv = { # https://nixos.asia/en/direnv
    enable = true;
    silent = true;
    mise.enable = false;
    nix-direnv.enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    # stdlib = "";
    # config.global = {};
  };
}
