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
      init.defaultBranch = "main";
      pull.rebase = false;

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
  };
}
