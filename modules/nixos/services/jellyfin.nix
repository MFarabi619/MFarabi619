{
  services.jellyfin =  {
    enable = true;
    user = "jellyfin";
    group = "jellyfin";
    openFirewall = false;
    # dataDir = "/var/lib/jellyfin"; # default
    # logDir = "\${cfg.dataDir}/log"; # default
    # cacheDir = "/var/cache/jellyfin"; # default
    # configDir = "\${cfg.dataDir}/config"; # default
  };
}
