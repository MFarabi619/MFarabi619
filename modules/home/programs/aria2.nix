{
  pkgs,
  ...
}:
{
  programs.aria2 = {
    enable = true;
    systemd.enable = pkgs.stdenv.isLinux;

    settings = {
      split = 16;
      continue = true;
      max-tries = 5;
      retry-wait = 10;
      remote-time = true;
      summary-interval = 5;
      connect-timeout = 30;
      min-split-size = "1M";
      max-file-not-found = 5;
      http-keep-alive = true;
      http-accept-gzip = true;
      download-result = "full";
      file-allocation = "none"; # Darwin: falloc unavailable, prealloc is slow
      check-certificate = true;
      auto-file-renaming = true;
      lowest-speed-limit = "100K"; # drop and reconnect if a stream stalls
      max-concurrent-downloads = 5;
      max-connection-per-server = 16;
      # dir = "/Users/mfarabi/Downloads";

      # enable-rpc = true;
      # rpc-listen-all = false; # localhost only
      # rpc-listen-port = 6800;
      # rpc-secret = "CHANGE_ME_RANDOM_TOKEN"; # see "RPC secret" section below
      # rpc-allow-origin-all = false; # no CORS — we don't need a web UI
      # rpc-save-upload-metadata = true;

      # force-save = true;
      # save-session-interval = 60;
      # save-session = "/Users/mfarabi/.cache/aria2/session.aria2";
      # input-file = "/Users/mfarabi/.cache/aria2/session.aria2"; # restore on start
    };
  };
}
