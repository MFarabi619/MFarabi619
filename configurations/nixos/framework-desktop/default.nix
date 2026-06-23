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
    ./dokploy.nix
    ./configuration.nix
    self.nixosModules.boot
    self.nixosModules.users
    self.nixosModules.default
    self.nixosModules.containers
  ];
}
