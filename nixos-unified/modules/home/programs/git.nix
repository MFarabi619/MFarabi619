{ config, ... }:
{
  programs = {
    git = {
      enable = true;
      userName = "Mumtahin Farabi";
      userEmail = "mfarabi619@gmail.com";
      ignores = [ "*~" "*.swp" ];
      # aliases = {
      #   ci = "commit";
      # };
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = false;
      };
    };
  };
}
