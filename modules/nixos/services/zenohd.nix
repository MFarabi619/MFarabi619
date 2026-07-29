{
  services.zenohd = {
    enable = true;
    settings = {
      metadata.name = "framework-desktop";
      adminspace.enabled = true;
      scouting.multicast.enabled = true;
      transport = {
        shared_memory.enabled = false;
        unicast = {
          max_sessions = 10000;
          open_timeout = 60000;
          accept_timeout = 60000;
          accept_pending = 10000;
        };
      };
    };
  };
}
