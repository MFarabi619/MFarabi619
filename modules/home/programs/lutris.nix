{
  pkgs,
  ...
}:
{
  programs.lutris = {
    # enable = pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64;
    enable = false; # FIXME: broken as of Thu May  7 12:45:25 EDT 2026
    winePackages = with pkgs; [
      wineWow64Packages.full
    ];
  };
}
