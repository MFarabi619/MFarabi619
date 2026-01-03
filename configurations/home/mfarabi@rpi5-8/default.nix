{
  flake,
  ...
}:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./home.nix
    ../../home/mfarabi.nix

    inputs.stylix.homeModules.stylix
    inputs.lazyvim.homeManagerModules.default
    inputs.nix-doom-emacs-unstraightened.homeModule

    self.homeModules.me
    self.homeModules.home
    self.homeModules.fonts
    self.homeModules.manual
    self.homeModules.accounts
    self.homeModules.services
    self.homeModules.editorconfig
  ];
}
