{
  config,
  ...
}:
{
  programs.git = {
    enable = true;

    settings = {
      alias.gama = "";
      pull.rebase = false;
      init.defaultBranch = "main";
      user.email = config.me.email;
      user.name = config.me.fullname;
    };

    signing = {
      format = "openpgp";
      signByDefault = false;
      key = config.accounts.email.accounts.personal.gpg.key;
    };

    ignores = [
      "*~"
      "*.swp"
    ];
  };
}
