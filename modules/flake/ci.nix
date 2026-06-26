{
  perSystem =
    { pkgs, ... }:
    let
      ci = pkgs.writeShellScriptBin "ci" ''
        exec om ci run --systems github:nix-systems/default "$@"
      '';
    in
    {
      apps.ci = {
        type = "app";
        program = "${ci}/bin/ci";
      };
    };
}
