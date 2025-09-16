{
  lib,
  pkgs,
  ...
}:
{
  services.activitywatch = lib.mkIf pkgs.stdenv.isLinux {
   enable = false;
    # settings = {
    #   port = 3012;

    #   custom_static = {
    #     my-custom-watcher = "${pkgs.my-custom-watcher}/share/my-custom-watcher/static";
    #     aw-keywatcher = "${pkgs.aw-keywatcher}/share/aw-keywatcher/static";
    #   };
    # };
    # extraOptions = [
    #   "--port"
    #   "5999"
    # ];
    watchers = {
     default = {
       name = "default";
        # settingsFilename = "config.toml";
      # settings = {};
      extraOptions = [];
     };
    };
};
}
