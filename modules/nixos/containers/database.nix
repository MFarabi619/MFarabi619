{
  containers = {
    database = {
      privateNetwork = true;
      hostAddress = "192.168.100.10";
      localAddress = "192.168.100.11";

      config =
        {
          config,
          pkgs,
          ...
        }:
        {
          services = {
            postgresql = {
              enable = true;
            };
          };
        };
    };
  };
}
