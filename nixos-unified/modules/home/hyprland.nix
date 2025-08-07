{ config, pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      rofi-wayland
      wl-clipboard
      noto-fonts
    ];

    sessionVariables = {
      NIXOS_OZONE_WL = "1";

      XDG_CACHE_HOME = config.xdg.cacheHome;
      XDG_CONFIG_HOME = config.xdg.configHome;
      XDG_DATA_HOME = config.xdg.dataHome;
      XDG_STATE_HOME = config.xdg.stateHome;
      XDG_RUNTIME_DIR = "/run/user/$(id -u)";

      XDG_DESKTOP_DIR = config.xdg.userDirs.desktop;
      XDG_DOCUMENTS_DIR = config.xdg.userDirs.documents;
      XDG_DOWNLOAD_DIR = config.xdg.userDirs.download;
      XDG_MUSIC_DIR = config.xdg.userDirs.music;
      XDG_PICTURES_DIR = config.xdg.userDirs.pictures;
      XDG_PUBLICSHARE_DIR = config.xdg.userDirs.publicShare;
      XDG_TEMPLATES_DIR = config.xdg.userDirs.templates;
      XDG_VIDEOS_DIR = config.xdg.userDirs.videos;

      # Additional XDG-related variables
      LESSHISTFILE = "/tmp/less-hist";
      PARALLEL_HOME = "${config.xdg.configHome}/parallel";
      SCREENRC = "${config.xdg.configHome}/screen/screenrc";
      ZSH_AUTOSUGGEST_STRATEGY = "history completion";

      # History configuration // explicit to not nuke history
      HISTFILE = "\${HISTFILE:-\$HOME/.zsh_history}";
      HISTSIZE = "10000";
      SAVEHIST = "10000";
      setopt_EXTENDED_HISTORY = "true";
      setopt_INC_APPEND_HISTORY = "true";
      setopt_SHARE_HISTORY = "true";
      setopt_HIST_EXPIRE_DUPS_FIRST = "true";
      setopt_HIST_IGNORE_DUPS = "true";
      setopt_HIST_IGNORE_ALL_DUPS = "true";
    };
  };

  xdg = {
    enable = true;
    mime.enable = true;
    mimeApps.enable = true;

    portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
      ];
      xdgOpenUsePortal = true;
      configPackages = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
        xdg-desktop-portal
        hyprland
      ];
    };

    userDirs = {
      enable = true;
      createDirectories = true;

      # Define standard XDG user directories
      desktop = "${config.home.homeDirectory}/Desktop";
      documents = "${config.home.homeDirectory}/Documents";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      publicShare = "${config.home.homeDirectory}/Public";
      templates = "${config.home.homeDirectory}/Templates";
      videos = "${config.home.homeDirectory}/Videos";
    };

    # Define standard XDG base directories
    cacheHome = "${config.home.homeDirectory}/.cache";
    configHome = "${config.home.homeDirectory}/.config";
    dataHome = "${config.home.homeDirectory}/.local/share";
    stateHome = "${config.home.homeDirectory}/.local/state";
  };

  programs = {
    waybar = {
      enable = true;
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

  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];

  wayland = {
    windowManager = {
      hyprland = {
        enable = true;
        package = null;
        systemd = {
          enable = true;
          enableXdgAutostart = true;
          variables = [
            "--all"
          ];
        };
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
            "GDK_SCALE,2"
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
            "$mainMod, G, togglegroup" # toggle focus/group
            "Alt, Return, fullscreen" # toggle focus/fullscreen
            "Ctrl+Alt, W, exec, killall waybar || waybar"
            "$mainMod,Q,killactive,"

            # Move/Change window focus
            "$mainMod, Left, movefocus, l"
            "$mainMod, Right, movefocus, r"
            "$mainMod, Up, movefocus, u"
            "$mainMod, Down, movefocus, d"
            "ALT,Tab,cyclenext"
            "ALT,Tab,bringactivetotop"

            # Move focused window around the current workspace
            "$mainMod+Shift+Ctrl, H, movewindow, l"
            "$mainMod+Shift+Ctrl, L, movewindow, r"
            "$mainMod+Shift+Ctrl, K, movewindow, u"
            "$mainMod+Shift+Ctrl, J, movewindow, d"
            ",XF86MonBrightnessDown,exec,brightnessctl set 5%-"
            ",XF86MonBrightnessUp,exec,brightnessctl set +5%"
          ]
          ++ (
            # Switch workspaces
            builtins.concatLists (
              builtins.genList (
                i:
                let
                  ws = i + 1;
                in
                [
                  "$mainMod, code:1${toString i}, workspace, ${toString ws}"
                  "$mainMod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
                ]
              ) 9
            )
          );
          bindm = [
            "$mainMod, mouse:272, movewindow"
            "$mainMod, mouse:273, resizewindow"
            "$mainMod, Z, movewindow"
            "$mainMod, X, resizewindow"
          ];
          exec-once = [
            "waybar"
            "kitty"
            "wl-paste --type text --watch cliphist store"
            "wl-paste --type image --watch cliphist store"
            "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
            "dbus-update-activation-environment --systemd --all"
            "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
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
          master = {
            new_status = "master";
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
            enable_swallow = false;
            vfr = true; # Variable Frame Rate
            vrr = 2; # Variable Refresh Rate  Might need to set to 0 for NVIDIA/AQ_DRM_DEVICES
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            force_default_wallpaper = 0;
          };

          render = {
            direct_scanout = 0;
          };

          monitor = ",1920x1080@144,auto,1.6";
          xwayland = {
            force_zero_scaling = true;
          };
        };
        extraConfig = "
        monitor=Virtual-1,4096x2160@165,auto,3.2
        windowrule = nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0
     ";
      };
    };
  };

  # services = {
  #   swww.enable = true;
  # };
}
