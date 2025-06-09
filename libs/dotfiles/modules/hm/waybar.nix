{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.waybar;
in
{
  options.hydenix.hm.waybar = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable bar module";
    };

    waybar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable waybar";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      lib.optionals cfg.waybar.enable [
        waybar # system bar
        playerctl # media player cli
        gobject-introspection # for python packages
        (python3.withPackages (ps: with ps; [ pygobject3 ])) # python with pygobject3
        python-pyamdgpuinfo # AMD GPU information library
        lm_sensors # sensors information library
      ];

    home.file = {

      # Modules for waybar
      # Note: some of these may not work for NixOS
      # TODO: review waybar modules for nix compatibility
      ".config/waybar/modules" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/waybar/modules";
        recursive = true;
      };
      ".config/waybar/config.ctl" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/waybar/config.ctl";
        force = true;
        mutable = true;
      };
      ".config/waybar/modules/header.jsonc" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/waybar/modules/header.jsonc";
        force = true;
        mutable = true;
      };
      ".config/waybar/modules/footer.jsonc" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/waybar/modules/footer.jsonc";
        mutable = true;
        force = true;
      };
      ".config/waybar/modules/style.css" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/waybar/modules/style.css";
        force = true;
        mutable = true;
      };
    };
  };
}
