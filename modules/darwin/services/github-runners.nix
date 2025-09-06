{
  services.github-runners = {
    macos = {
      enable = false;
      nodeRuntimes = "node22";
      url = "https://github.com/mira-amm/mira-amm-web";
      tokenFile = ./.runner.token;
      ephemeral = false;
      extraLabels = [ "macbook-air" ];
    };
  };
}
