{ lib, pkgs, ... }:
{
  env = {
    # PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_26}/bin/node";
    LIBRARY_PATH = lib.mkIf (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64) "/opt/homebrew/lib";
  };
}
