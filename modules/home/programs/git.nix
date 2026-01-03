{
  config,
  ...
}:
{
  programs.git = {
    enable = true;

    settings = {
      pull.rebase = false;
      init.defaultBranch = "main";

      user = {
        name = config.me.fullname;
        email = config.me.email;
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
