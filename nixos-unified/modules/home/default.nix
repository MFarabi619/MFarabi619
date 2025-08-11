{ pkgs, lib, ... }:
{
  imports = [
    ./editorconfig.nix
    ./fonts.nix
    ./home.nix
    ./manual.nix
    ./nix.nix
    ./nix-index.nix
    ./me.nix
    # ]
    # ++ lib.optionals (!(pkgs.stdenv.pkgs.stdenv.hostPlatform.isAarch64 && pkgs.stdenv.isLinux)) [
  ];
}
