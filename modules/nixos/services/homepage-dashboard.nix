{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8088;
    openFirewall = false;
    # environmentFile = "";
    allowedHosts = "homepage.openws.org";

    # settings = {};

    widgets = [
      {
        resources = {
          cpu = true;
          disk = "/";
          memory = true;
        };
      }
      {
        search = {
          provider = "duckduckgo";
          target = "_blank";
        };
      }
    ];

    services = [
      {
        "Sites" = [
          {
            "Landing Page" = {
              description = "Beep Boop";
              href = "https://openws.org";
            };
          }
          {
            "Docs" = {
              description = "Snowflake go brrrr";
              href = "https://docs.openws.org";
            };
          }
          {
            "AI Chat" = {
              description = "Open WebUI + Ollama";
              href = "https://ai.openws.org";
            };
          }
        ];
      }
      {
        "Operating Systems" = [
          {
            "NixOS" = {
              description = "Snowflake go brrrr";
              href = "https://demo.openws.org";
            };
          }
          {
            "Arch Linux" = {
              description = "Linus go brrrr";
              href = "https://archlinux.openws.org";
            };
          }
          {
            "FreeBSD" = {
              description = "Beastie go brrrr";
              href = "https://freebsd.openws.org";
            };
          }
          {
            "GNU GUIX" = {
              description = "Vroom vroom";
              href = "https://guix.openws.org";
            };
          }
        ];
      }
    ];
  };
}
