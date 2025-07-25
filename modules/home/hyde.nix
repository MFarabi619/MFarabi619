{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hydenix.hm.hyde;
in
{

  options.hydenix.hm.hyde = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.hydenix.hm.enable;
      description = "Enable hyde module";
    };
  };

  # TODO: review stateful files in hyde module
  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;
    home = {
      packages = with pkgs; [
        hydenix.hyde
        Bibata-Modern-Ice
        Tela-circle-dracula
        kdePackages.kconfig # TODO: not sure if this is still needed
        wf-recorder # screen recorder for wlroots-based compositors such as sway
      ];

      # fixes cava from not initializing on boot
      activation.createCavaConfig = lib.hm.dag.entryAfter [ "mutableGeneration" ] ''
        mkdir -p "$HOME/.config/cava"
        touch "$HOME/.config/cava/config"
        chmod 644 "$HOME/.config/cava/config"
      '';

      file = {
        # Regular files (processed first)
        ".config/hyde/wallbash" = {
          source = "${pkgs.hydenix.hyde}/Configs/.config/hyde/wallbash";
          recursive = true;
          force = true;
          mutable = true;
        };

        ".config/systemd/user/hyde-config.service" = {
          source = "${pkgs.hydenix.hyde}/Configs/.config/systemd/user/hyde-config.service";
        };
        ".config/systemd/user/hyde-ipc.service" = {
          source = "${pkgs.hydenix.hyde}/Configs/.config/systemd/user/hyde-ipc.service";
        };

        ".local/bin/hyde-shell" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/bin/hyde-shell";
          executable = true;
        };

        # TODO: requires nix-ld
        ".local/bin/hydectl" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/bin/hydectl";
          executable = true;
        };

        ".local/bin/hyde-ipc" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/bin/hyde-ipc";
          executable = true;
        };

        ".local/lib/hyde" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/lib/hyde";
          recursive = true;
          force = true;
          mutable = true;
          executable = true;
        };

        ".local/lib/hyde/globalcontrol.sh" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/lib/hyde/globalcontrol.sh";
          executable = true;
        };

        ".local/share/fastfetch/presets/hyde" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/share/fastfetch/presets/hyde";
          recursive = true;
        };
        ".local/share/hyde" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/share/hyde";
          recursive = true;
          executable = true;
          force = true;
          mutable = true;
        };
        ".config/MangoHud/MangoHud.conf" = {
          source = "${pkgs.hydenix.hyde}/Configs/.config/MangoHud/MangoHud.conf";
        };
        ".local/share/kio/servicemenus/hydewallpaper.desktop" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/share/kio/servicemenus/hydewallpaper.desktop";
        };
        ".local/share/kxmlgui5/dolphin/dolphinui.rc" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/share/kxmlgui5/dolphin/dolphinui.rc";
        };

        ".config/electron-flags.conf" = {
          source = "${pkgs.hydenix.hyde}/Configs/.config/electron-flags.conf";
        };

        ".local/share/icons/Wallbash-Icon" = {
          source = "${pkgs.hydenix.hyde}/share/icons/wallbash";
          force = true;
          recursive = true;
          mutable = true;
        };

        # stateful files
        ".config/hyde/config.toml" = {
          source = "${pkgs.hydenix.hyde}/Configs/.config/hyde/config.toml";
          force = true;
          mutable = true;
        };
        ".local/share/dolphin/view_properties/global/.directory" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/share/dolphin/view_properties/global/.directory";
          force = true;
          mutable = true;
        };
        ".local/share/icons/default/index.theme" = {
          source = "${pkgs.hydenix.hyde}/Configs/.local/share/icons/default/index.theme";
          force = true;
          mutable = true;
        };
        ".local/share/themes/Wallbash-Gtk" = {
          source = "${pkgs.hydenix.hyde}/share/themes/Wallbash-Gtk";
          recursive = true;
          force = true;
          mutable = true;
        };
      };
    };
  };
}
