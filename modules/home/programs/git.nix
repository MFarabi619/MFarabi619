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
      format = "ssh";
      signByDefault = true;
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
    };

    ignores = [
      "*~"
      "*.swp"
    ];
  };
}
