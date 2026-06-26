{
  config,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      ci = pkgs.writeShellScriptBin "ci" ''
        exec om ci run --systems ${lib.concatStringsSep "," config.systems} "$@"
      '';
    in
    {
      apps.ci = {
        type = "app";
        program = "${ci}/bin/ci";
      };
    };
}
