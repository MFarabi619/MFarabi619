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
      pull.rebase = false;
      init.defaultBranch = "main";

      user = {
        name = "Mumtahin Farabi";
        email = "mfarabi619@gmail.com";
      };
      alias = {
        gama = "";
        ga = "git add .";
      };
     };

    signing = {
      # format = "ssh";
      # signByDefault = true;
    };

    ignores = [
      "*~"
      "*.swp"
    ];
  };
}
