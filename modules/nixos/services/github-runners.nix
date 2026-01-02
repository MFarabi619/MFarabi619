{
  pkgs,
  ...
}:
{
  services.github-runners = {
    nixos = {
      enable = false;
      replace = false;
      ephemeral = false;
      url = "https://github.com/MFarabi619/MFarabi619";

      extraLabels = [
        "nixos"
      ];

      nodeRuntimes = [
        "node22"
      ];

      extraPackages = with pkgs; [
        pnpm
        devenv
        xorg.xvfb
        playwright
        playwright-test
      ];

      extraEnvironment = {
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = true;
        PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";
      };

      # serviceOverrides = {};
      # user = null;
      # group = null;
      # tokenFile = ./.runner.token;
      # runnerGroup = "self-hosted";
      # name = "nixos"; # defaults to hostname, changing this triggers new registration
      # workDir = null; # triggers new registration on change
    };

    macos = {
      enable = false;
      ephemeral = false;
      nodeRuntimes = "node22";
      tokenFile = ./.runner.token;
      extraLabels = [ "macbook-air" ];
      url = "https://github.com/mira-amm/mira-amm-web";
    };
  };
}
