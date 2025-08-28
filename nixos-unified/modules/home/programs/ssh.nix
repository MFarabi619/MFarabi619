{
  programs.ssh = {
    enable = true;
    # enableDefaultConfig = false;
    # includes = [];
    # extraConfig = "";
    # extraOptionOverrides = {};
    matchBlocks = {
      "rpi5" = {
        port = 22;
        host = "rpi5";
        user = "mfarabi";
        hostname = "192.168.1.115";

        checkHostIP = true;
        addKeysToAgent = "yes";

        # sendEnv = {};
        setEnv.TERM = "xterm-kitty";

        # addressFamily = null; # "any" | "inet" | "inet6"
        # certificateFile = [ ./.file ];

        # compression = false;
        # controlmaster = null; # "yes" | "no" | "ask" | "auto" | "autoask"
        # controlPath = null; # path to control socket used for connection sharing
        # controlPersist = "10am"; # whether control socket should remain open in backgroung

        # identityFile = [];
        # identityAgent = [];
        # identitiesOnly = false;

        # userKnownHostsFile = ./file;
        # hashKnownHosts = null;

        # serverAliveInterval = 5;
        # serverAliveCountMax = 5;

        # proxyJump = "";
        # proxyCommand = "";

        #  match = ''
        #  host  canonical
        #  host  exec "ping -c1 -q 192.168.17.1"
        # '';

        # dynamicForwards  = [
        #   {
        #     "name" = {
        #       address = "localhost";
        #       port = 8080;
        #     };
        #   }
        # ];

        # remoteForwards = [
        #   {
        #     bind = {
        #       address = "10.0.0.13";
        #       port = 8080;
        #     };
        #     host = {
        #       address = "10.0.0.13";
        #       port = 80;
        #     };
        #   }
        # ];

        # localForwards = [
        #   {
        #     bind = {
        #       address = "10.0.0.13";
        #       port = "8080";
        #     };
        #     host = {
        #       address = "10.0.0.13";
        #       port = "80";
        #     };
        #   }
        # ];
      };
    };
  };
}
