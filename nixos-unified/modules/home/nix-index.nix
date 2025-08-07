{ flake, ... }:
{
  imports = [
    # NOTE: The nix-index DB is slow to search, until
    # https://github.com/nix-community/nix-index-database/issues/130
    flake.inputs.nix-index-database.homeModules.nix-index
  ];

  programs.nix-index-database.comma.enable = true;
}
