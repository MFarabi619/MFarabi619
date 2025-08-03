{ flake, pkgs, ... }:
{
  imports = [
    ./programs
  ];

  home = {
    shell = {
      enableShellIntegration = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    packages = with pkgs; [
    # ==========  Doom Emacs ===========
    # clang
    cmake # vterm compilation and more
    coreutils
    binutils # native-comp needs 'as', provided by this
    gnutls # for TLS connectivity
    epub-thumbnailer # dired epub previews
    poppler-utils # dired pdf previews
    openscad
    openscad-lsp
    vips # dired image previews
    imagemagick # for image-dired
    tuntox # collab
    sqlite # :tools lookup & :lang org +roam
    ispell # spelling
    nil # nix lang formatting
    shellcheck # shell script formatting
    # texlive     # :lang latex & :lang org (latex previews)

    rofi-wayland
    wl-clipboard

    omnix

    tree
    gnumake

    # Nix dev
    cachix
    nil # Nix language server
    nix-info
    nixpkgs-fmt

    # On ubuntu, we need this less for `man home-configuration.nix`'s pager to
    # work.
    less

    # Setup Claude Code using Google Vertex AI Platform
    # https://github.com/juspay/vertex
    flake.inputs.vertex.packages.${system}.default
  ];

  sessionVariables = {
    NIXOS_OZONE_WL = "1";
    };
  };

  # Programs natively supported by home-manager.
  # They can be configured in `programs.*` instead of using home.packages.
  programs = {
    tmate = {
      enable = true;
      #host = ""; #In case you wish to use a server other than tmate.io
    };
    kitty = {
      enable = true;
      font = {
       name = "JetBrainsMono Nerd Font";
       package = pkgs.nerd-fonts.jetbrains-mono;
       size = 9;
      };
      enableGitIntegration = true;
      shellIntegration = {
        enableBashIntegration = true;
        enableZshIntegration = true;
      };
      settings = {
        window_padding_width = 10;
        tab_bar_edge = "top";
      };
      # themeFile = "";
    };
    vivaldi = {
      enable = true;
    };
    waybar = {
      enable = true;
      # settings = [ ];
      # style = ''
      # '';
    };
    fastfetch = {
     enable = true;
     # settings = {

     # };
    };
    # rofi = {
    #   enable = true;
    #   location = "center";
    #   # font = "";
    #   # terminal = "${pkgs.kitty}/";
    #   plugins = with pkgs; [
    #   ];
    #   modes = [
    #   "drun"
    #   "emoji"
    #   "ssh"
    #   ];
    #   # pass = {
    #   #   enable = true;
    #   #   };
    # };
  };

wayland = {
  windowManager = {
    hyprland = {
      enable = true;
      systemd.enable = false;
      settings = {
        env = [
          "XDG_CURRENT_DESKTOP,Hyprland"
          "XDG_SESSION_TYPE,wayland"
          "XDG_SESSION_DESKTOP,Hyprland"
          "QT_QPA_PLATFORM,wayland;xcb"
          "QT_QPA_PLATFORMTHEME,qt6ct"
          "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
          "QT_AUTO_SCREEN_SCALE_FACTOR,1"
          "MOZ_ENABLE_WAYLAND,1"
          "GDK_SCALE,1"
        ];
        "$mainMod" = "SUPER";
        "$editor" = "nvim";
        "$file" = "dolphin";
        "$term" = "kitty";
        "$browser" = "vivaldi";
        "$menu" = "rofi -show drun";
        bind = [
          # Apps
          "$mainMod, T, exec, $term"
          "$mainMod, E, exec, $file"
          "$mainMod, C, exec, $editor"
          "$mainMod, F, exec, $browser"

          # Window/Session
          "$mainMod, W, togglefloating" # toggle focus/float
          "$mainMod, G, togglegroup"    # toggle focus/group
          "Alt, Return, fullscreen"     # toggle focus/fullscreen
          "Ctrl+Alt, W, exec, killall waybar || waybar"

          # Move/Change window focus
          "$mainMod, Left, movefocus, l"
          "$mainMod, Right, movefocus, r"
          "$mainMod, Up, movefocus, u"
          "$mainMod, Down, movefocus, d"
          "Alt, Tab, movefocus, d"

          # Move focused window around the current workspace
          "$mainMod+Shift+Ctrl, H, movewindow, l"
          "$mainMod+Shift+Ctrl, L, movewindow, r"
          "$mainMod+Shift+Ctrl, K, movewindow, u"
          "$mainMod+Shift+Ctrl, J, movewindow, d"
        ] ++ (
            # Switch workspaces
            builtins.concatLists (builtins.genList (i:
              let ws = i + 1;
              in [
                "$mainMod, code:1${toString i}, workspace, ${toString ws}"
                "$mainMod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
              ]
            )
          9)
        );
        bindm = [
          "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
          "$mainMod, Z, movewindow"
          "$mainMod, X, resizewindow"
        ];
        exec-once = [
         "waybar"
         "wl-paste --type text --watch cliphist store"
         "wl-paste --type image --watch cliphist store"
        ];
        animations = {
        enabled = false;
        };
        decoration = {
          blur = {
            enabled = true;
            passes = 1;
            size = 3;
            vibrancy = 0.1696;
          };
        shadow = {
          color = "rgba(1a1a1aee)";
          enabled = true;
          range = 4;
          render_power = 3;
        };
        active_opacity = 1.0;
        inactive_opacity = 1.0;
        rounding = 10;
        };
        dwindle = {
          preserve_split = true;
          pseudotile = true;
        };
        general = {
          allow_tearing = false;
          border_size = 5;
          gaps_in = 5;
          gaps_out = 20;
          layout = "master";
          resize_on_border = true;
        };
        gestures = {
          workspace_swipe = true;
          workspace_swipe_fingers = 3;
          workspace_swipe_forever = true;
          workspace_swipe_invert = false;
        };
        input = {
          kb_layout = "us";
          kb_options = "ctrl:nocaps";

          touchpad = {
            natural_scroll = true;
          };
        };
        misc = {
          vrr = 0;
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          force_default_wallpaper = 0;
        };

        monitor = ",highres,auto,auto";
        xwayland = {
          force_zero_scaling = true;
        };
      };
    };
  };
};

services = {
  swww.enable = true;
    # cachix-agent = {
    #   name = "nixos-msi-gs65";
    #   enable = true;
    #   verbose = true;
    # };
};
}
