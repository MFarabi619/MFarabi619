{
  programs = {
    eza = {
      enable = true;
      icons = "auto";
      colors = "auto";
      git = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraOptions = [
        "--group-directories-first"
      ];
    };
  };
}
