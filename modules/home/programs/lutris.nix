{
  pkgs,
  ...
}:
{
  programs.lutris = {
    enable = pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64;
    winePackages = with pkgs; [
      wineWow64Packages.full
    ];
  };
}
