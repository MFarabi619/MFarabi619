{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    # inputs.nix-doom-emacs-unstraightened.homeModule
    # ../../../../modules/home/stylix.nix
    # ../../../../modules/home/manual.nix
    # ../../../../modules/home/home.nix
    # ../../../../modules/home/editorconfig.nix
    # ../../../../modules/home/services.nix
    # ../../../../modules/home/doom-emacs.nix
    # ../../../../modules/home/aerospace.nix
    # ../../../../modules/home/programs
    ./programs.nix
    ./darwin.nix
  ];

}
