{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      legacyPackages.homeConfigurations = lib.mkIf pkgs.stdenv.isDarwin (lib.mkForce { });
    };
}
