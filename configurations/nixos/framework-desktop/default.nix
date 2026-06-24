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
    ./configuration.nix
    self.nixosModules.boot
    self.nixosModules.users
    self.nixosModules.default
    self.nixosModules.containers
  ];
}
