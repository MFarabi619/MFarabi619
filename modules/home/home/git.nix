{ flake, ... }:
let
  inherit (flake.config) me;
in
{
  home.shellAliases = {
    lg = "lazygit";
  };

  programs = {
    git = {
      enable = true;
      userName = me.fullname;
      userEmail = me.email;
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = false;
      };
    };
  };
}
