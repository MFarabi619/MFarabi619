{
  flake,
  ...
}:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.homeModules.default
  ];

  stylix.overlays.enable = false;

  home.stateVersion = "25.05";
}
