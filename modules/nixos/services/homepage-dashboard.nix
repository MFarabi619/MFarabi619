{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8088;
    openFirewall = false;
    # environmentFile = "";
    allowedHosts = "openws.org";

    settings = {
      theme = "dark";
      cardBlur = "3xl";
      useEqualHeights = true;
      title = "🕹️ Microvisor Systems 🕹️";
      description = "🤖 Beep boop, from bootloader to browser 🤖";
      favicon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/fe07ec17f23aeb202d11333d8faa62d3b79a103e/assets/nix-mfarabi.svg";

      background = {
        image = "https://github.com/MFarabi619/MFarabi619/blob/main/assets/homepage-background.png?raw=true";
      };

      quicklaunch = {
        provider = "google";
        hideVisitURL = "true";
        searchDescriptions = "true";
        hideInternetSearch = "true";
        showSearchSuggestions = "true";
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
          cputemp = true;
          tempmin = 0;
          tempmax = 100;
          uptime = true;
          refresh = 3000;
          network = true;
          units = "metric";
          diskUnits = "bytes";
        };
      }
    ];

    services = [
      {
        "📜 Sites" = [
          {
            "Landing Page" = {
              href = "https://openws.org";
              siteMonitor = "https://openws.org";
              icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/fe07ec17f23aeb202d11333d8faa62d3b79a103e/assets/nix-mfarabi.svg";
            };
          }
          {
            "Docs" = {
              href = "https://docs.openws.org";
              siteMonitor = "https://ai.openws.org";
              icon = "https://avatars.githubusercontent.com/u/128791862?s=200&v=4";
            };
          }
          {
            "Arch Linux Mirror" = {
              href = "https://mirror.openws.org";
              siteMonitor = "https://mirror.openws.org";
              icon = "https://upload.wikimedia.org/wikipedia/commons/1/13/Arch_Linux_%22Crystal%22_icon.svg";
            };
          }
          {
            "Grafana" = {
              href = "https://openws.org/grafana";
              siteMonitor = "https://openws.org/grafana";
              icon = "https://upload.wikimedia.org/wikipedia/commons/3/3b/Grafana_icon.svg";
            };
          }
          {
            "🏗️ Netdata" = {
              href = "https://openws.org/netdata";
              # siteMonitor = "https://openws.org/netdata";
              icon = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/netdata.svg";
            };
          }
        ];
      }
      {
        "🤖 AI/ML" = [
          {
            "Open WebUI" = {
              href = "https://ai.openws.org";
              siteMonitor = "https://ai.openws.org";
              icon = "https://avatars.githubusercontent.com/u/158137808?s=200&v=4";
            };
          }
          {
            "LLM Gateway" = {
              href = "https://llm-gateway.openws.org";
              # siteMonitor = "https://llm-gateway.openws.org";
              icon = "https://raw.githubusercontent.com/theopenco/llmgateway/refs/heads/main/apps/docs/public/favicon/android-chrome-512x512.png";
            };
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
                  href = "https://openbsd.openws.org";
                  # siteMonitor = "https://openbsd.openws.org";
                  icon = "https://avatars.githubusercontent.com/u/929183?s=200&v=4";
                };
              }
              {
                "🏗️ Darwin" = {
                  href = "https://darwin.openws.org";
                  # siteMonitor = "https://darwin.openws.org";
                  icon = "https://www.svgrepo.com/show/303484/apple1-logo.svg";
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
                  icon = "https://raw.githubusercontent.com/MFarabi619/MFarabi619/fbbc70b0bdba558139e2f62ba06723a8bc678799/assets/nix.svg";
                };
              }
              {
                "🏗️ Arch" = {
                  href = "https://archlinux.openws.org";
                  # siteMonitor = "https://archlinux.openws.org";
                  icon = "https://upload.wikimedia.org/wikipedia/commons/1/13/Arch_Linux_%22Crystal%22_icon.svg";
                };
              }
              {
                "🏗️ Debian" = {
                  href = "https://debian.openws.org";
                  # siteMonitor = "https://debian.openws.org";
                  icon = "https://upload.wikimedia.org/wikipedia/commons/6/66/Openlogo-debianV2.svg";
                };
              }
              {
                "🏗️ Ubuntu" = {
                  href = "https://ubuntu.openws.org";
                  # siteMonitor = "https://ubuntu.openws.org";
                  icon = "https://upload.wikimedia.org/wikipedia/commons/9/9e/UbuntuCoF.svg";
                };
              }
              {
                "Raspberry Pi 5 (Trixie)" = {
                  href = "https://rpi5.openws.org";
                  siteMonitor = "https://rpi5.openws.org";
                  icon = "https://www.svgrepo.com/show/303239/raspberry-pi-logo.svg";
                };
              }
              {
                "🏗️ Gentoo" = {
                  href = "https://gentoo.openws.org";
                  # siteMonitor = "https://gentoo.openws.org";
                  icon = "https://www.gentoo.org/assets/img/logo/gentoo-signet.svg";
                };
              }
            ];
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
        ];
      }
    ];
  };
}
