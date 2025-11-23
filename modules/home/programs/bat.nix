{
  pkgs,
  ...
}:
{
  programs.bat = {
    enable = true;

    extraPackages = with pkgs.bat-extras; [
      batman
      batpipe
      # batgrep
    ];

    # config = {
    #   pager = "less -FR";
    # };
  };
}
