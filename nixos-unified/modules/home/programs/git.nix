{
  # config,
  ...
}:
{
  programs.git = {
    enable = true;
    userName = "Mumtahin Farabi";
    userEmail = "mfarabi619@gmail.com";
    # signing = {
    #  format = "";
    # };
    ignores = [
      "*~"
      "*.swp"
    ];
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
    lfs = {
      enable = false;
    };
  };
}
