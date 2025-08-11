{
  services.github-runners = {
    nixos = {
      enable = false;
      nodeRuntimes = "node22";
      url = "https://github.com/MFarabi619/MFarabi619";
      # tokenFile = ./.runner.token;
    };
  };
}
