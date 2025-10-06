{
  imports = [ ../../../../../modules/shared/nix ];

  config,
  lib,
  ...
}:

let
  cfg = config.hydenix.nix;
in
{
  options.hydenix.nix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nix module";
    };
  };

  config = lib.mkIf cfg.enable {
    nix = {
      settings = {
        auto-optimise-store = true;
        experimental-features = [
          "nix-command"
          "flakes"
        ];

      };
    };
  };
}
