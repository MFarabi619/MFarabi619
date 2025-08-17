{
  description = "Nix-Ubuntu + Home Manager Server";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    system-manager = {
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      system-manager,
      ...
    }@inputs:
    {
      systemConfigs.default = system-manager.lib.makeSystemConfig {
        modules = [
          ./system.nix
        ];
      };
    };
}
