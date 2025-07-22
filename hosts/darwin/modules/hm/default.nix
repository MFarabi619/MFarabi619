{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    inputs.nix-doom-emacs-unstraightened.homeModule
    ../../../../modules/hm/stylix.nix
    ../../../../modules/hm/manual.nix
    ../../../../modules/hm/home.nix
    ../../../../modules/hm/editorconfig.nix
    ../../../../modules/hm/services.nix
    ../../../../modules/hm/doom-emacs.nix
    ../../../../modules/hm/aerospace.nix
    ../../../../modules/hm/programs
    ./programs.nix
    ./darwin.nix
  ];

}
