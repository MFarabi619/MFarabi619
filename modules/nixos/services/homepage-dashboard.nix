{
  config,
  pkgs,
  ...
}:
let
  background = pkgs.fetchurl {
    name = "homepage-background.png";
    url = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/homepage-background.png";
    hash = "sha256-01vx98qijcsc1nqank2chdiq6zj0gp6zifjncv4368zblys51i65";
  };

  package = pkgs.homepage-dashboard.overrideAttrs (oldAttrs: {
    postInstall = ''
      mkdir -p $out/share/homepage/public/images
      ln -s ${background} $out/share/homepage/public/images/homepage-background.png
    '';
  });
in
{
  services.homepage-dashboard = {
    # inherit package;
    enable = config.networking.hostName == "framework-desktop";
    # environmentFile = "";
    allowedHosts = "openws.org";

    settings = {
      theme = "dark";
      cardBlur = "3xl";
      useEqualHeights = true;
      headerStyle = "boxedWidgets";
      title = "🕹️ Microvisor Systems 🕹️";
      # background = "/images/homepage-background.png";
      background = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/homepage-background.png";
      description = "🤖 Beep boop, from bootloader to browser 🤖";
      favicon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/fe07ec17f23aeb202d11333d8faa62d3b79a103e/assets/nix-mfarabi.svg";

      quicklaunch = {
        # target = "_blank";
        provider = "google";
        hideVisitURL = "false";
        searchDescriptions = "true";
        hideInternetSearch = "false";
        showSearchSuggestions = "true";
        mobileButtonPostion = "bottom-right";
      };
    };

    widgets = [
      {
        logo = {
          icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/fe07ec17f23aeb202d11333d8faa62d3b79a103e/assets/nix-mfarabi.svg";
        };
      }
      {
        greeting = {
          text_size = "xl";
          text = "🕹️ Microvisor Systems 🕹️";
        };
      }
      {
        datetime = {
          text_size = "l";
          format = {
            hour12 = "true";
            dateStyle = "long";
            timeStyle = "short";
          };
        };
      }
      {
        resources = {
          cpu = true;
          disk = "/";
          memory = true;
          tempmin = 0;
          tempmax = 100;
          uptime = true;
          cputemp = true;
          refresh = 1000;
          network = true;
          units = "metric";
          diskUnits = "bytes";
        };
      }
      {
        search = {
          focus = false;
          target = "_blank";
          provider = "duckduckgo";
          showSearchSuggestions = true;
        };
      }
      # {
      #   caddy = {
      #     url = "https://openws.org";
      #   };
      # }
      # {
      #   netdata = {
      #     url = "127.0.0.1:19999";
      #   };
      # }
    ];

    services = [
      {
        "Sites" = [
          {
            "Landing Page" = {
              href = "https://microvisor.systems";
              siteMonitor = "https://microvisor.systems";
              icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/fe07ec17f23aeb202d11333d8faa62d3b79a103e/assets/nix-mfarabi.svg";
            };
          }
          {
            "Docs" = {
              href = "https://docs.openws.org/view/index";
              siteMonitor = "https://docs.openws.org";
              icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/likec4-symbol.svg";
            };
          }
          {
            "Arch Linux Mirror" = {
              href = "https://mirror.openws.org";
              siteMonitor = "https://mirror.openws.org";
              icon = "arch-linux.svg";
            };
          }
          {
            "🏗️ Netdata" = {
              href = "https://www.netdata.cloud";
              # siteMonitor = "https://www.netdata.cloud";
              icon = "netdata.svg";
            };
          }
        ];
      }
      {
        "Services" = [
          {
            "AI/ML" = [
              {
                "Open WebUI" = {
                  href = "https://ai.openws.org";
                  siteMonitor = "https://ai.openws.org";
                  icon = "open-webui.svg";
                };
              }
              {
                "🏗️ LLM Gateway" = {
                  href = "https://llmgateway.io";
                  icon = "https://raw.githubusercontent.com/theopenco/llmgateway/refs/heads/main/apps/docs/public/favicon/android-chrome-512x512.png";
                };
              }
              {
                "🏗️ Burn" = {
                  href = "https://burn.dev";
                  icon = "https://raw.githubusercontent.com/tracel-ai/burn/main/assets/backend-chip.png";
                };
              }
            ];
          }
          {
            "IoT & Robotics" = [
              {
                "Grafana" = {
                  href = config.services.grafana.settings.server.root_url;
                  siteMonitor = config.services.grafana.settings.server.root_url;
                  icon = "grafana.svg";
                };
              }
            ];
          }
          {
            "Security" = [
              {
                "🏗️ Authentik" = {
                  href = "https://goauthentik.io";
                  icon = "authentik.svg";
                };
              }
            ];
          }
          {
            "CI/CD" = [
              {
                "Dokploy" = {
                  icon = "dokploy.svg";
                  href = "https://admin.openws.org";
                  siteMonitor = "https://admin.openws.org";
                };
              }
              {
                "🏗️ Kubernetes" = {
                  icon = "kubernetes.svg";
                  href = "https://kubernetes.io";
                };
              }
            ];
          }
          {
            "🛖 Userspace Environments" = [
              {
                "Emacs - Doom" = {
                  href = "https://emacs.openws.org";
                  siteMonitor = "https://emacs.openws.org";
                  icon = "https://user-images.githubusercontent.com/590297/85930281-0d379c00-b889-11ea-9eb8-6f7b816b6c4a.png";
                };
              }
              {
                "Neovim - Lazyvim" = {
                  href = "https://neovim.openws.org";
                  siteMonitor = "https://neovim.openws.org";
                  icon = "https://upload.wikimedia.org/wikipedia/commons/3/3a/Neovim-mark.svg";
                };
              }
              {
                "Penpot" = {
                  icon = "penpot.svg";
                  href = "https://penpot.openws.org";
                  siteMonitor = "https://penpot.openws.org";
                };
              }
            ];
          }
        ];
      }
      {
        "🧮 Operating Systems" = [
          {
            "UNIX" = [
              {
                "FreeBSD" = {
                  href = "https://freebsd.openws.org";
                  siteMonitor = "https://freebsd.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/freebsd-symbol-orb.png";
                };
              }
              {
                "🏗️ OpenBSD" = {
                  href = "https://openbsd.org";
                  # siteMonitor = "https://openbsd.openws.org";
                  icon = "https://avatars.githubusercontent.com/u/929183?s=200&v=4";
                };
              }
              {
                "🏗️ Darwin" = {
                  href = "https://en.wikipedia.org/wiki/Darwin_(operating_system)";
                  # siteMonitor = "https://darwin.openws.org";
                  icon = "https://www.svgrepo.com/show/303484/apple1-logo.svg";
                };
              }
              {
                "🏗️ DoomBSD" = {
                  href = "https://www.linkedin.com/posts/mfarabi_announcing-the-doombsd-project-an-advanced-activity-7341980656043786240-uw9M/";
                  # siteMonitor = "https://darwin.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/doombsd-symbol-orb.svg";
                };
              }
            ];
          }
          {
            "GNU/Linux" = [
              {
                "🏗️ GNU GUIX" = {
                  href = "https://guix.openws.org";
                  # siteMonitor = "https://guix.openws.org";
                  icon = "https://images.icon-icons.com/2699/PNG/512/gnu_guix_logo_icon_171081.png";
                };
              }
              {
                "NixOS" = {
                  href = "https://demo.openws.org";
                  siteMonitor = "https://demo.openws.org";
                  icon = "nixos.svg";
                };
              }
              {
                "🏗️ Arch Linux" = {
                  href = "https://archlinux.org";
                  # siteMonitor = "https://archlinux.openws.org";
                  icon = "arch-linux.svg";
                };
              }
              {
                "🏗️ Apollyon Linux" = {
                  href = "https://archlinux.org";
                  # siteMonitor = "https://archlinux.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/apollyon-linux-logo.png";
                };
              }
              {
                "🏗️ Debian" = {
                  href = "https://www.debian.org";
                  # siteMonitor = "https://debian.openws.org";
                  icon = "debian-linux.svg";
                };
              }
              {
                "🏗️ Ubuntu" = {
                  href = "https://ubuntu.com";
                  # siteMonitor = "https://ubuntu.openws.org";
                  icon = "ubuntu-linux.svg";
                };
              }
              {
                "Raspberry Pi 5 (Trixie)" = {
                  icon = "raspberry-pi.svg";
                  href = "https://rpi5.openws.org";
                  siteMonitor = "https://rpi5.openws.org";
                };
              }
              {
                "🏗️ Gentoo" = {
                  href = "https://gentoo.org";
                  # siteMonitor = "https://gentoo.openws.org";
                  icon = "gentoo-linux.svg";
                };
              }
            ];
          }
        ];
      }
    ];

    bookmarks = [
      {
        Developer = [
          {
            Github = [
              {
                icon = "github.png";
                href = "https://github.com/MFarabi619";
              }
            ];
          }
        ];
      }
      {
        Social = [
          {
            LinkedIn = [
              {
                icon = "linkedin.png";
                href = "https://linkedin.com/company/microvisor-systems";
              }
            ];
          }
        ];
      }
    ];

    customCSS = ''
      .information-widget-greeting span {
        background: linear-gradient(
          90deg,
          #ffd200 0%,
          #ec8c78 33%,
          #e779c1 67%,
          #58c7f3 100%
        );

        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
      }
    '';
  };
}
