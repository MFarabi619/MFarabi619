{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.hyprland;
in
{

  options.hydenix.hm.hyprland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable hyprland module";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra config for hyprland";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      hyprcursor
      hyprutils
      xdg-desktop-portal-hyprland
      hyprpicker
      hypridle
    ];

    home.activation.createHyprConfigs = lib.hm.dag.entryAfter [ "mutableGeneration" ] ''
      mkdir -p "$HOME/.config/hypr/animations"
      mkdir -p "$HOME/.config/hypr/themes"

      touch "$HOME/.config/hypr/animations/theme.conf"
      touch "$HOME/.config/hypr/themes/colors.conf"
      touch "$HOME/.config/hypr/themes/theme.conf"
      touch "$HOME/.config/hypr/themes/wallbash.conf"

      chmod 644 "$HOME/.config/hypr/animations/theme.conf"
      chmod 644 "$HOME/.config/hypr/themes/colors.conf"
      chmod 644 "$HOME/.config/hypr/themes/theme.conf"
      chmod 644 "$HOME/.config/hypr/themes/wallbash.conf"
    '';

    home.file = {
      ".config/hypr/hyprland.conf" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/hyprland.conf";
        force = true;
      };
      ".config/hypr/hyde.conf".source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/hyde.conf";
      ".config/hypr/keybindings.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/keybindings.conf";
      ".config/hypr/monitors.conf".source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/monitors.conf";
      ".config/hypr/nvidia.conf".source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/nvidia.conf";
      ".config/hypr/userprefs.conf" = {
        text = ''
          ${cfg.extraConfig}
        '';
        force = true;
      };
      ".config/hypr/windowrules.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/windowrules.conf";
      ".config/hypr/animations.conf" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations.conf";
        force = true;
        mutable = true;
      };
      ".config/hypr/animations/classic.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/classic.conf";
      ".config/hypr/animations/diablo-1.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/diablo-1.conf";
      ".config/hypr/animations/diablo-2.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/diablo-2.conf";
      ".config/hypr/animations/dynamic.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/dynamic.conf";
      ".config/hypr/animations/disable.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/disable.conf";
      ".config/hypr/animations/eevee-1.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/eevee-1.conf";
      ".config/hypr/animations/eevee-2.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/eevee-2.conf";
      ".config/hypr/animations/high.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/high.conf";
      ".config/hypr/animations/low-1.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/low-1.conf";
      ".config/hypr/animations/low-2.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/low-2.conf";
      ".config/hypr/animations/minimal-1.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/minimal-1.conf";
      ".config/hypr/animations/minimal-2.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/minimal-2.conf";
      ".config/hypr/animations/moving.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/moving.conf";
      ".config/hypr/animations/optimized.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/optimized.conf";
      ".config/hypr/animations/standard.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/standard.conf";
      ".config/hypr/animations/vertical.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/vertical.conf";
      ".config/hypr/animations/LimeFrenzy.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/animations/LimeFrenzy.conf";
      ".config/hypr/hypridle.conf".source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/hypridle.conf";

      # Shaders
      ".config/hypr/shaders/blue-light-filter.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/blue-light-filter.frag";
      ".config/hypr/shaders/color-vision.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/color-vision.frag";
      ".config/hypr/shaders/.compiled.cache.glsl" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/.compiled.cache.glsl";
        force = true;
        mutable = true;
      };
      ".config/hypr/shaders.conf" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders.conf";
        force = true;
        mutable = true;
      };
      ".config/hypr/shaders/custom.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/custom.frag";
      ".config/hypr/shaders/disable.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/disable.frag";
      ".config/hypr/shaders/grayscale.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/grayscale.frag";
      ".config/hypr/shaders/invert-colors.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/invert-colors.frag";
      ".config/hypr/shaders/oled.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/oled.frag";
      ".config/hypr/shaders/oled-saver.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/oled-saver.frag";
      ".config/hypr/shaders/paper.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/paper.frag";
      ".config/hypr/shaders/vibrance.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/vibrance.frag";
      ".config/hypr/shaders/wallbash.frag".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/wallbash.frag";
      ".config/hypr/shaders/wallbash.inc".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/shaders/wallbash.inc";

      # Workflows
      ".config/hypr/workflows.conf" = {
        source = "${pkgs.hydenix.hyde}/Configs/.config/hypr/workflows.conf";
        force = true;
        mutable = true;
      };
      ".config/hypr/workflows/default.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/workflows/default.conf";
      ".config/hypr/workflows/editing.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/workflows/editing.conf";
      ".config/hypr/workflows/gaming.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/workflows/gaming.conf";
      ".config/hypr/workflows/powersaver.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/workflows/powersaver.conf";
      ".config/hypr/workflows/snappy.conf".source =
        "${pkgs.hydenix.hyde}/Configs/.config/hypr/workflows/snappy.conf";
    };
  };
}
