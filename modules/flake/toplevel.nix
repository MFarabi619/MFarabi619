# Top-level flake glue to get our configuration working
{ inputs, lib, self, ... }:

{
  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
  ];
  perSystem = { self', pkgs, system, ... }: {
    # For 'nix fmt'
    formatter = pkgs.nixpkgs-fmt;

    # Enables 'nix run' to activate.
    packages.default = self'.packages.activate;

    legacyPackages.homeConfigurations =
      let
        homeDir = "${self}/configurations/home";
      in
      lib.mkForce (
        lib.mapAttrs
          (name: _: self.nixos-unified.lib.mkHomeConfiguration pkgs "${homeDir}/${name}")
          (lib.filterAttrs
            (name: type: type == "directory" && import "${homeDir}/${name}/system.nix" == system)
            (builtins.readDir homeDir)
          )
      );
  };
}
