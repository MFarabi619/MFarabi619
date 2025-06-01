{ ... }:

{
  imports = [
    # ./example.nix - add your modules here
  ];

  home = {

    packages = [
      # pkgs.vscode - hydenix's vscode version
      # pkgs.userPkgs.vscode - your personal nixpkgs version
    ];
  };

  programs = {
  fd.enable = true;
  ripgrep.enable = true;
    vivaldi.enable = true;
    yazi = {
      enable = true;
      enableZshIntegration = true;
    };
    btop.enable = true;
    lazydocker.enable = true;
    lazygit = {
      enable = true;
      settings = {
        gui = {
          nerdFontsVersion = "3";
          parseEmoji = true;
          scrollPastBottom = true;
          scrollOffBehaviour = "jump";
          sidePanelWidth = 0.33;
          switchTabsWithPanelJumpKeys = true;
        };
        os = {
          edit = "emacsclient -n {{filename}}";
          editAtLine = "emacsclient -n +{{line}} {{filename}}";
          openDirInEditor = "emacsclient {{dir}}";
          editInTerminal = false; # Suspend until an edit process returns
        };
        git = {
          branchPrefix = "mfarabi/";
        };
        promptToReturnFromSubprocess = true;
      };
    };
    bat.enable = true;
    direnv.enable = true;
    gh = {
      enable = true;
      settings = {
        git_protocol = "https";
      };
    };
    gh-dash.enable = true;
    k9s.enable = true;
    bun.enable = true;
    kubecolor = {
      enable = true;
      enableAlias = true;
    };
    superfile.enable = true;
    zed-editor = {
      enable = true;
      userSettings = {
        "base_keymap" = "VSCode";
        telemetry = {
          metrics = false;
          diagnostics = false;
        };
        vim_mode = true;
        "ui_font_size" = 16;
        "buffer_font_size" = 16;
        theme = {
          mode = "system";
          light = "One Light";
          dark = "Gruvbox Dark Hard";
        };
        "pane_split_direction_vertical" = "left";
        "project_panel" = {
          dock = "right";
        };
        "outline_panel" = {
          dock = "right";
        };
        "git_panel" = {
          dock = "right";
        };
      };
      extensions = [
        "html" "toml" "dockerfile" "git-firefly" "nix" "vue" "sql" "ruby" "latex" "svelte" "lua" "docker-compose" "graphql" "csv" "basher" "nginx" "solidity" "unocss" "stylint"
      ];
    };
    zsh = {
      shellAliases = {
        cat = "bat";
      };
    };
    zellij = {
      enable = true;
      enableZshIntegration = true;
    };
  };

  hydenix.hm = {
    enable = true;

    comma.enable = true; # useful nix tool to run software without installing it first
    dolphin.enable = true;
    editors = {
      enable = true; # enable editors module
      neovim = true; # enable neovim module
      vscode = {
        enable = true; # enable vscode module
        wallbash = true; # enable wallbash extension for vscode
      };
      vim = true; # enable vim module
      default = "emacs"; # default text editor
    };
    fastfetch.enable = true; # fastfetch configuration
    firefox = {
      enable = true; # enable firefox module
      useHydeConfig = false; # use hyde firefox configuration and extensions
      useUserChrome = true; # if useHydeConfig is true, apply hyde userChrome CSS customizations
      useUserJs = true; # if useHydeConfig is true, apply hyde user.js preferences
      useExtensions = true; # if useHydeConfig is true, install hyde firefox extensions
    };
    git = {
      enable = true;
      name = "Mumtahin Farabi"; # git user name eg "John Doe"
      email = "mfarabi619@gmail.com"; # git user email eg "john.doe@example.com"
    };
    hyde.enable = true; # enable hyde module
    hyprland.enable = true; # enable hyprland module
    lockscreen = {
      enable = true; # enable lockscreen module
      hyprlock = true; # enable hyprlock lockscreen
      swaylock = false; # enable swaylock lockscreen
    };
    notifications.enable = true;
    qt.enable = true;
    rofi.enable = true;
    screenshots = {
      enable = true; # enable screenshots module
      grim.enable = true; # enable grim screenshot tool
      slurp.enable = true; # enable slurp region selection tool
      satty.enable = true; # enable satty screenshot annotation tool
      swappy.enable = true; # enable swappy screenshot editor
    };
    shell = {
      enable = true;
      zsh = {
        enable = true;
        configText = ""; # zsh config text
      };
      bash.enable = true;
      fish.enable = false;
      pokego.enable = false; # enable Pokemon ASCII art scripts
    };
    social = {
      enable = true; # enable social module
      discord.enable = false; # enable discord module
      webcord.enable = false; # enable webcord module
      vesktop.enable = true; # enable vesktop module
    };
    spotify.enable = false;
    swww.enable = true; # enable swww wallpaper daemon
    terminals = {
      enable = true;
      kitty = {
        enable = true;
        configText = "";
      };
    };
    waybar.enable = true;
    wlogout.enable = true;
    xdg.enable = true;
    theme = {
      enable = true;
      active = "Catppuccin Mocha"; # active theme name
      themes = [
        "Catppuccin Mocha"
        "Catppuccin Latte"
        "Abyss Green"
        "Abyssal Wave"
        "Amethyst Aura"
        "Another World"
        "Bad Blood"
        "Blue Sky"
        "Cat Latte"
        "Code Garden"
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
        "Piece Of Mind"
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
