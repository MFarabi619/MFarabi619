{
  programs = {
    eza = {
      enable = true;
      icons = "always";
      colors = "always";
      git = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraOptions = [
        "--group-directories-first"
      ];
    };
  };
}
