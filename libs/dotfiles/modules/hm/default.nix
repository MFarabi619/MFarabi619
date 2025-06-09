{
  lib,
  ...
}:

{
  imports = [
    # ./example.nix - add your modules here
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
    direnv.enable = true;
    fd.enable = true;
    ripgrep.enable = true;
    pandoc.enable = true;
    texlive.enable = true;
    tex-fmt.enable = true;
    vivaldi.enable = true;
    superfile.enable = true;
    mu.enable = true;
    nh.enable = true;
    jq.enable = true;
    java.enable = true;
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
          editInTerminal = false;
        };
        git = {
          branchPrefix = "mfarabi/";
        };
        promptToReturnFromSubprocess = true;
      };
    };
    gh-dash.enable = true;
    gh = {
      enable = true;
      settings = {
        git_protocol = "https";
      };
    };
    k9s.enable = true;
    kubecolor = {
      enable = true;
      enableAlias = true;
    };
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
    yazi = {
      enable = true;
      enableZshIntegration = true;
      manager = {
        show_hidden = true;
        show_symlink = true;
      };
    };
    zsh = {
      shellAliases = {
        cat = "bat";
      };
    };
    zellij = {
      enable = true;
      # enableZshIntegration = true;
      # attachExistingSession = true;
    };
    doom-emacs = {
      enable = true;
      doomDir = ../doom;
      extraPackages = epkgs: [
        epkgs.pdf-tools
        epkgs.editorconfig
        epkgs.shfmt
        epkgs.nixfmt
        epkgs.npm
        epkgs.rustic
        epkgs.lsp-java
        epkgs.lsp-docker
        epkgs.lsp-latex
        epkgs.lsp-pyright
        epkgs.lsp-tailwindcss
        epkgs.lsp-treemacs
        epkgs.lsp-haskell
        epkgs.typescript-mode
        epkgs.jtsx
        epkgs.yaml
        epkgs.xclip
        epkgs.wttrin
        epkgs.vue3-mode
      ];
      # provideEmacs = false;
    };
  };

  services = {
    emacs = {
      enable = true;
      socketActivation.enable = true;
      client.enable = true;
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
    git = {
      enable = true;
      name = "Mumtahin Farabi";
      email = "mfarabi619@gmail.com";
    };
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
      zsh = {
        enable = true;
        configText = ""; # zsh config text
      };
      bash.enable = false;
      fish.enable = false;
      pokego.enable = false;
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
