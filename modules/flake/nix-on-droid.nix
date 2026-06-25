{ inputs, root, ... }:
{
  flake.nixOnDroidConfigurations.default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
    home-manager-path = inputs.home-manager.outPath;
    extraSpecialArgs = {
      inherit inputs;
    };

    pkgs = import inputs.nixpkgs {
      system = "aarch64-linux";
      overlays = [
        inputs.nix-on-droid.overlays.default
      ];
    };

    modules = [
      "${root}/modules/nixos/time.nix"
      "${root}/configurations/nixos/nix-on-droid/terminal.nix"
      "${root}/configurations/nixos/nix-on-droid/environment.nix"
      "${root}/configurations/nixos/nix-on-droid/nix-on-droid.nix"
      "${root}/configurations/nixos/nix-on-droid/home-manager.nix"
      "${root}/configurations/nixos/nix-on-droid/android-integration.nix"
    ];
  };
}
