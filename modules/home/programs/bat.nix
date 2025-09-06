{pkgs,...}:
{
  home.shellAliases = {
    cat = "bat";
    man = "batman";
    grep = "batgrep";
    # TODO: add batpipe
  };
  programs.bat = {
      enable = true;
      config = {
        pager = "less -FR";
      };
      extraPackages = with pkgs.bat-extras; [
        batman
        batpipe
        batgrep
      ];
    };
}
