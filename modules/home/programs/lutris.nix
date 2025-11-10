{
  pkgs,
  ...
}:
{
  programs.lutris = {
    enable = pkgs.stdenv.isLinux;
    winePackages = with pkgs; [
      wineWow64Packages.full
    ];
  };
}
