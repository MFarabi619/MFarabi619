{
  config,
  pkgs,
  ...
}:
{
  services.github-runners = {
    nixos-1 = {
      enable = config.networking.hostName == "framework-desktop";
      # enable = false;
      # group = null;
      replace = true;
      # name = "nixos"; # defaults to hostname, changing this triggers new registration
      # workDir = null; # triggers new registration on change
      user = "mfarabi";
      ephemeral = false;
      # runnerGroup = "self-hosted";
      url = "https://github.com/apidae-systems/platform";
      tokenFile = "/var/lib/secrets/github-actions-runner.token";

      extraLabels = [
        "nixos"
      ];

      nodeRuntimes = [
        "node24"
      ];

      extraPackages = with pkgs; [
        jq
        pnpm
        xvfb
        pulumi
        devenv
        direnv
        platformio
        playwright
        playwright-test
      ];

      # extraEnvironment = {
      #   PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
      #   PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_24}/bin/node";
      # };

      serviceOverrides = {
        PrivateUsers = false;
        SystemCallFilter = "";
        RestrictNamespaces = false;
        SystemCallArchitectures = "native";
      };
    };

    # nixos-2 = {
    #   enable = config.networking.hostName == "framework-desktop";
    #   # workDir = null; # triggers new registration on change
    #   replace = true;
    #   user = "mfarabi";
    #   ephemeral = true;
    #   url = "https://github.com/apidae-systems/platform";
    #   tokenFile = "/var/lib/secrets/github-actions-runner.token";
    #
    #   extraLabels = [
    #     "nixos"
    #   ];
    #
    #   extraPackages = with pkgs; [
    #     devenv
    #   ];
    #
    #   serviceOverrides = {
    #     PrivateUsers = false;
    #     SystemCallFilter = "";
    #     RestrictNamespaces = false;
    #     SystemCallArchitectures = "native";
    #   };
    # };

    # nixos-3 = {
    #   enable = config.networking.hostName == "framework-desktop";
    #   # workDir = null; # triggers new registration on change
    #   replace = true;
    #   user = "mfarabi";
    #   ephemeral = true;
    #   url = "https://github.com/apidae-systems/platform";
    #   tokenFile = "/var/lib/secrets/github-actions-runner.token";

    #   extraLabels = [
    #     "nixos"
    #   ];

    #   extraPackages = with pkgs; [
    #     devenv
    #   ];

    #   serviceOverrides = {
    #     PrivateUsers = false;
    #     SystemCallFilter = "";
    #     RestrictNamespaces = false;
    #     SystemCallArchitectures = "native";
    #   };
    # };

    # nixos-4 = {
    #   enable = config.networking.hostName == "framework-desktop";
    #   # workDir = null; # triggers new registration on change
    #   replace = true;
    #   user = "mfarabi";
    #   ephemeral = true;
    #   url = "https://github.com/apidae-systems/platform";
    #   tokenFile = "/var/lib/secrets/github-actions-runner.token";

    #   extraLabels = [
    #     "nixos"
    #   ];

    #   extraPackages = with pkgs; [
    #     devenv
    #   ];

    #   serviceOverrides = {
    #     PrivateUsers = false;
    #     SystemCallFilter = "";
    #     RestrictNamespaces = false;
    #     SystemCallArchitectures = "native";
    #   };
    # };
  };
}
