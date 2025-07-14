{ inputs, config, lib, pkgs, ... }:

{
  imports = [
    inputs.lazyvim.homeManagerModules.default
    inputs.nix-doom-emacs-unstraightened.homeModule
    ../../../../modules/hm/doom-emacs.nix
    ../../../../modules/hm/git.nix
    ../../../../modules/hm/lazygit.nix
    ../../../../modules/hm/gh.nix
    ../../../../modules/hm/yazi.nix
    ./stylix.nix
  ];

  home = {
    stateVersion = "25.05";
    username = "mfarabi";
    packages = with pkgs; [
      # ============== 🤪 =================
      asciiquarium
      cowsay
      cmatrix
      figlet
      nyancat
      lolcat
      # hollywood
      # ============= 🧑‍💻🐞‍ ================
      # pnpm
      devenv
      nix-inspect
      tgpt
      # ugm
      lazyjournal
      pik
      systemctl-tui
      # virt-viewer
      # ===================
      zsh-powerlevel10k
      meslo-lgs-nf
    ];

    shell = {
enableShellIntegration = true;
enableZshIntegration = true;
    };
  };

  editorconfig.enable = true;

  manual = {
    manpages.enable = true;
html.enable = true;
    json.enable = true;
  };

  services = {
home-manager = {
# autoUpgrade = {
# enable = true;
#         frequency = "daily";
#       };
    };
  };


fonts = {
  fontconfig = {
    enable = true;
    defaultFonts = {
      serif = [
          "JetBrainsMono Nerd Font"
        ];
      sansSerif = [
        "JetBrainsMono Nerd Font"
        ];
      monospace = [
        "JetBrainsMono Nerd Font"
        ];
      emoji = [
        "Noto Color Emoji"
        ];
      };
    };
};

  targets = {
    darwin = {
      linkApps = {
        enable = true;
      };
    search = "Google";
    currentHostDefaults = {
      "com.apple.controlcenter" = {
        BatteryShowPercentage = true;
        };
      };
    defaults = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      NSGlobalDomain = {
          AppleMetricUnits = true;
            AppleMesurementUnits = "Centimeters";
            };
          "com.apple.finder" = {
            AppleShowAllFiles = true;
            showPathBar = true;
            ShowStatusBar = true;
            };
          "com.apple.dock" = {
            autohide = true;
            tileSize = 48;
            orientation = "bottom";
            };
          "com.apple.menuextra.clock" = {
            ShowAMPM = true;
            };
          };
    #      keybindings = {
    # "^u" = "deleteToBeginningOfLine:";
    #  "^w" = "deleteWordBackward:";
    #      };
        };
  };

  programs = {
    home-manager.enable = true;
    aerospace = {
      enable = true;
      userSettings = {
        start-at-login = true;
        accordion-padding = 30;
        mode.main.binding = {
          alt-enter = ''
              exec-and-forget osascript -e '
              tell application "Kitty"
                  do script
                  activate
              end tell'
              '';
          alt-tab = "workspace-back-and-forth";
          };
        gaps = {
            outer.left = 8;
            outer.bottom = 8;
            outer.top = 8;
            outer.right = 8;
          };
        on-focus-changed = [
          "move-mouse monitor-lazy-center"
        ];
        on-focused-monitor-changed = [
          "move-mouse monitor-lazy-center"
        ];
      };
    };
    go = {
      enable = true;
    };
    jq = {
      enable = true;
    };
    fzf = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    kitty = {
      enable = true;
      shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
      };
      enableGitIntegration = true;
    };
    neovim = {
      enable = true;
      defaultEditor = true;
    };
    lazysql.enable = true;
    lazyvim = {
      enable = true;
      plugins = with pkgs; [
        vimPlugins.base16-nvim
      ];
      extras = {
        util = {
          dot.enable = true;
        };
        ui = {
          mini-animate.enable = true;
        };
        editor = {
          fzf.enable = true;
          # neotree.enable = true;
        };
        test.core.enable = true;
        lang = {
          nix.enable = true;
          json.enable = true;
          # markdown.enable = true;
          tailwind.enable = true;
          typescript.enable = true;
          python.enable = true;
        };
        dap.core.enable = true;
      };
    };
    bat.enable = true;
    fastfetch = {
      enable = true;
        settings = {
      };
    };
    eza = {
      enable = true;
      icons = "auto";
      colors = "auto";
      git = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraOptions = [
        "--group-directories-first"
      ];
    };
    nix-index = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
    zsh = {
      enable = true;
      autocd = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      initContent = lib.mkBefore ''
          source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

          [[ -f ~/.p10k.zsh ]] && source ~/MFarabi619/libs/dotfiles/hosts/darwin/modules/hm/.p10k.zsh
        '';
      oh-my-zsh = {
        enable = true;
        plugins =
          [
            "sudo"
            "git"
            "colored-man-pages"
            "colorize"
            "docker"
            "docker-compose"
            "git"
            "kubectl"
          ]
          ++ lib.optionals pkgs.stdenv.isDarwin [
            "dash"
            "macos"
          ];
      };

      shellAliases = {
        cat = "bat";
      };
    };
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
    nh.enable = true;
    k9s.enable = true;
    kubecolor = {
      enable = true;
      enableAlias = true;
    };
    zellij = {
      enable = true;
      settings = {
    };
      # enableZshIntegration = true;
      # attachExistingSession = true;
    };
  };
}
