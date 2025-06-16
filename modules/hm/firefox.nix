{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.firefox;
in
{
  options.hydenix.hm.firefox = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable firefox module";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      firefox # browser
    ];

    home.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
    };
  };
}
