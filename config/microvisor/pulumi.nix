{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:
let
  cfg = config.microvisor.pulumi;
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  options.microvisor.pulumi = {
    enable = lib.mkEnableOption "Pulumi IAC.";
  };

  config = lib.mkIf cfg.enable {
    packages = with pkgs-unstable; [
      pulumi
      pulumi-esc
      # pulumiPackages.pulumi-go
    ];
  };
}
