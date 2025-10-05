{
  programs.atuin = {
   enable = true;
   daemon.enable = true;
   enableZshIntegration = true;
   enableBashIntegration = true;
    # settings = {
    #   sync_frequency = "5m";
    #   sync_address = "https://api.atuin.sh";
    #   search_mode = "prefix";
    # };
    # flags = [
    #  "--disable-up-arrow"
    #  "--disable-ctrl-r"
    # ];
  };
}
