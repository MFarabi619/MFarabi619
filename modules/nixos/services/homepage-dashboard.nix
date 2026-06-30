{
  config,
  ...
}:
{
  services.homepage-dashboard = rec {
    enable = config.networking.hostName == "framework-desktop";
    allowedHosts = "openws.org";

    settings = {
      theme = "dark";
      cardBlur = "3xl";
      useEqualHeights = true;
      headerStyle = "boxedWidgets";
      title = "🕹️ Microvisor Systems 🕹️";
      # background = "/images/homepage-background.png";
      description = "🤖 Beep boop, from bootloader to browser 🤖";
      favicon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/nix-mfarabi.svg";
      background = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/homepage-background.png";

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
          icon = settings.favicon;
        };
      }
      {
        greeting = {
          text_size = "xl";
          text = settings.title;
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
            "Landing Page" = rec {
              href = "https://microvisor.systems";
              icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/nix-mfarabi.svg";
              siteMonitor = href;
            };
          }
          {
            "Docs" = {
              href = "https://docs.openws.org/view/index";
              siteMonitor = "https://docs.openws.org";
              icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/likec4.svg";
            };
          }
          # {
          #   "Arch Linux Mirror" = rec {
          #     href = "https://mirror.openws.org";
          #     siteMonitor = href;
          #     icon = "arch-linux.svg";
          #   };
          # }
          {
            # "🏗️ Netdata" = {
            #   href = "https://www.netdata.cloud";
            #   # siteMonitor = "https://www.netdata.cloud";
            #   icon = "netdata.svg";
            # };
          }
        ];
      }
      {
        "Services" = [
          {
            "AI/ML" = [
              {
                "Open WebUI" = rec {
                  href = config.services.open-webui.environment.WEBUI_URL;
                  siteMonitor = href;
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
              {
                "Velxio" = {
                  href = "https://velxio.openws.org";
                  siteMonitor = "https://velxio.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/velxio.svg";
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
                "Dokploy" = rec {
                  icon = "dokploy.svg";
                  href = "https://admin.openws.org";
                  siteMonitor = href;
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
                "Emacs - Doom" = rec {
                  # siteMonitor = href;
                  href = "https://emacs.openws.org";
                  icon = "https://user-images.githubusercontent.com/590297/85930281-0d379c00-b889-11ea-9eb8-6f7b816b6c4a.png";
                };
              }
              {
                "Neovim - Lazyvim" = rec {
                  # siteMonitor = href;
                  href = "https://neovim.openws.org";
                  icon = "https://upload.wikimedia.org/wikipedia/commons/3/3a/Neovim-mark.svg";
                };
              }
              {
                "Penpot" = rec {
                  # siteMonitor = href;
                  icon = "penpot.svg";
                  href = "https://penpot.openws.org";
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
                "🏗️ Apache NuttX" = {
                  href = "https://nuttx.apache.org";
                  # siteMonitor = "https://nuttx.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/nuttx.png";
                };
              }
              {
                "FreeBSD" = {
                  href = "https://freebsd.openws.org";
                  # siteMonitor = "https://freebsd.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/freebsd-symbol-orb.png";
                };
              }
              {
                "🏗️ OpenBSD" = {
                  href = "https://openbsd.org";
                  # siteMonitor = "https://openbsd.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/openbsd.png";
                };
              }
              {
                "🏗️ OpenIndiana" = {
                  href = "https://docs.openindiana.org/misc/openindiana";
                  # siteMonitor = "https://openindiana.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/openindiana.svg";
                };
              }
              {
                "🏗️ OmniOS" = {
                  href = "https://omnios.org";
                  # siteMonitor = "https://omnios.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/omnios.svg";
                };
              }
              {
                "🏗️ Darwin" = {
                  href = "https://en.wikipedia.org/wiki/Darwin_(operating_system)";
                  # siteMonitor = "https://darwin.openws.org";
                  icon = "https://www.svgrepo.com/show/303484/apple1-logo.svg";
                };
              }
              # {
              #   "🏗️ DoomBSD" = {
              #     href = "https://www.linkedin.com/posts/mfarabi_announcing-the-doombsd-project-an-advanced-activity-7341980656043786240-uw9M/";
              #     # siteMonitor = "https://doombsd.openws.org";
              #     icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/doombsd-orb.svg";
              #   };
              # }
            ];
          }
          {
            "GNU/Linux" = [
              {
                "🏗️ Zephyr RTOS" = {
                  href = "https://www.zephyrproject.org";
                  # siteMonitor = "https://zephyr.openws.org";
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/zephyr.png";
                };
              }
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
                  # siteMonitor = "https://demo.openws.org";
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
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/refs/heads/main/assets/icons/apollyon-linux.png";
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
                  # href = "https://rpi5.openws.org";
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
