{
  lib,
  ...
}:

{
  imports = [
      ./doom-emacs.nix
      ./zsh.nix
      ./git.nix
      ./lazygit.nix
      ./gh.nix
      ./zed.nix
      ./yazi.nix
  ];

  home = {
    packages = [
      # pkgs.vscode - hydenix's vscode version
      # pkgs.userPkgs.vscode - your personal nixpkgs version
    ];

    file = {
      ".config/hypr/userprefs.conf" = lib.mkForce {
        text = ''
          $editor = emacs
          $browser = vivaldi

          input {
            kb_options = ctrl:nocaps
            touchpad {
            natural_scroll = true
            }
          }

          unbind = Shift, F11
          unbind = Alt, Return

          $wm=Window Management
          $d=[$wm]

          bindd = Alt, Return, $d toggle fullscreen, fullscreen

          animations {
            enabled = true
          }
        '';
        force = true;
        mutable = true;
      };
    };
  };

  programs = {
    bat.enable = true;
    bun.enable = true;
    btop.enable = true;
    lazydocker.enable = true;
    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    fd.enable = true;
    ripgrep.enable = true;
    pandoc.enable = true;
    texlive.enable = true;
    tex-fmt.enable = true;
    vivaldi.enable = true;
    chromium = {
     enable = true;
     extensions = [
       {id = "dldjpboieedgcmpkchcjcbijingjcgok";} # fuel wallet
       {id = "gfbliohnnapiefjpjlpjnehglfpaknnc";} # surfingkeys
     ];
    };
    superfile.enable = true;
    mu.enable = true;
    nh.enable = true;
    java.enable = true;
    k9s.enable = true;
    kubecolor = {
      enable = true;
      enableAlias = true;
    };
    zellij = {
      enable = true;
      # enableZshIntegration = true;
      # attachExistingSession = true;
    };
};

  hydenix.hm = {
    enable = true;
    hyde.enable = true;
    hyprland.enable = true;
    fastfetch.enable = true;
    dolphin.enable = true;
    notifications.enable = true;
    qt.enable = true;
    rofi.enable = true;
    swww.enable = true;
    waybar.enable = true;
    wlogout.enable = true;
    xdg.enable = true;
    spotify.enable = false;
    comma.enable = true;
    editors = {
      enable = true;
      neovim = true;
      vscode = {
        enable = true;
        wallbash = true;
      };
      vim = true;
      default = "emacs";
    };
    firefox = {
      enable = true;
      useHydeConfig = false; # use hyde firefox configuration and extensions
      useUserChrome = true;  # if useHydeConfig is true, apply hyde userChrome CSS customizations
      useUserJs = true;      # if useHydeConfig is true, apply hyde user.js preferences
      useExtensions = true;  # if useHydeConfig is true, install hyde firefox extensions
    };
    git.enable = false;
    lockscreen = {
      enable = true;
      hyprlock = true;
      swaylock = false;
    };
    screenshots = {
      enable = true;
      grim.enable = true;    # screenshot tool
      satty.enable = true;   # screenshot annotation tool
      slurp.enable = true;   # region selection tool
      swappy.enable = true;  # screenshot editor
    };
    shell = {
      enable = true;
      bash.enable = false;
      zsh = {
        enable = true;
        configText = "";
      };
    };
    social = {
      enable = true;
      discord.enable = true;
      webcord.enable = true;
      vesktop.enable = true;
    };
    terminals = {
      enable = true;
      kitty = {
        enable = true;
        configText = "";
      };
    };
    theme = {
      enable = true;
      active = "Green Lush";
      themes = [
       "Catppuccin Mocha"
       "Catppuccin Latte"
       "Abyss Green"
       "Abyssal Wave"
       "Amethyst Aura"
       # "Another World"
       "Bad Blood"
       "Blue Sky"
       "Cat Latte"
       # "Code Garden"
       "Cosmic Blue"
       "Crimson Blade"
       "Crimson Blue"
       "Decay Green"
       "Doom Bringers"
       "Dracula"
       "Edge Runner"
       "Eletra"
       "Eternal Arctic"
       "Ever Blushing"
       "Frosted Glass"
       "Graphite Mono"
       "Green Lush"
       "Greenify"
       "Grukai"
       "Gruvbox Retro"
       "Hack the Box"
       "Ice Age"
       "Mac OS"
       "Material Sakura"
       "Monokai"
       "Monterey Frost"
       "Moonlight"
       "Nightbrew"
       "Nordic Blue"
       "Obsidian Purple"
       "One Dark"
       "Oxo Carbon"
       "Paranoid Sweet"
       # "Piece Of Mind"
       "Pixel Dream"
       "Rain Dark"
       "Red Stone"
       "Rose Pine"
       "Scarlet Night"
       "Sci fi"
       "Solarized Dark"
       "Synth Wave"
       "Tokyo Night"
       "Vanta Black"
       "Windows 11"
      ]; # Full list: https://github.com/richen604/hydenix/tree/main/hydenix/sources/themes
    };
  };
}
