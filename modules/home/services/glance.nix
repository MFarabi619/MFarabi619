{
  lib,
  pkgs,
  ...
}:
{
  services.glance = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = false;
    settings = {
      pages = [
        {
          columns = [
            {
              size = "full";
              widgets = [
                {
                  type = "calendar";
                }
              ];
            }
          ];
          name = "Calendar";
        }
      ];
    };
  };
}
