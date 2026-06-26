{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.statix =
        pkgs.runCommandLocal "statix-check"
          { nativeBuildInputs = [ pkgs.statix ]; }
          ''
            set -e
            cd ${inputs.self}
            statix check flake.nix
            statix check modules
            statix check configurations
            touch $out
          '';
    };
}
