{
  containers = {
    database = {
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
