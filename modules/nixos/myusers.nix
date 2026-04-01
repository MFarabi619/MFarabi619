# List of users for darwin or nixos system and their top-level configuration.
{
  lib,
  pkgs,
  flake,
  config,
  ...
}:
let
  inherit (flake.inputs) self;
  mapListToAttrs =
    m: f:
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = f name;
      }) m
    );
in
{
  options.myusers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    description = "List of usernames";
    defaultText = "All users under ./configuration/users are included by default";
    default =
      let
        dirContents = builtins.readDir (self + /configurations/home);
        fileNames = builtins.attrNames dirContents; # Extract keys: [ "mfarabi.nix" ]
        regularFiles = builtins.filter (name: dirContents.${name} == "regular") fileNames; # Filter for regular files
        baseNames = map (name: builtins.replaceStrings [ ".nix" ] [ "" ] name) regularFiles; # Remove .nix extension
      in
      baseNames;
  };

  config = {
    # For home-manager to work.
    # https://github.com/nix-community/home-manager/issues/4026#issuecomment-1565487545
    users.users = mapListToAttrs config.myusers (
      name:
      lib.optionalAttrs pkgs.stdenv.isDarwin {
        home = "/Users/${name}";
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        isNormalUser = true;
        shell = pkgs.zsh;

        extraGroups = [
          "dialout"
        ];
      }
    );

    home-manager = {
      backupFileExtension = "hm-bak";
      users = mapListToAttrs config.myusers (name: {
        imports = [
          (self + /configurations/home/${name}.nix)
          # ]
          # ++ lib.optionals pkgs.stdenv.isLinux [
          #   flake.inputs.stylix.homeModules.stylix
        ];
      });
    };
  };
}
