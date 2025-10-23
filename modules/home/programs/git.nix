{
  # config,
  ...
}:
{
  programs.git = {
    enable = true;
    lfs.enable = false;
    maintenance.enable = false;
    settings = {
      user = {
        name = "Mumtahin Farabi";
        email = "mfarabi619@gmail.com";
      };
      alias = {
        ga = "git add .";
        gama = "";
      };
     };

    # signing = {
    #   # format = "ssh";
    #   signByDefault = true;
    # };

    ignores = [
      "*~"
      "*.swp"
    ];

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };
}
