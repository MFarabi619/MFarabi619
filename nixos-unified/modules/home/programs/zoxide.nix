{
  home.shellAliases.z = "zoxide";
  programs.zoxide = {
    enable = true;
    options = ["--cmd cd"];
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
}
