{
  # config,
  ...
}:
{
  programs.git = {
    enable = true;
    lfs.enable = false;
    maintenance.enable = false;
    userName = "Mumtahin Farabi";
    userEmail = "mfarabi619@gmail.com";

    # signing = {
    #   # format = "ssh";
    #   signByDefault = true;
    # };

    ignores = [
      "*~"
      "*.swp"
    ];

    aliases = {
      ga = "git add .";
      gama = "";
    };

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };
}
