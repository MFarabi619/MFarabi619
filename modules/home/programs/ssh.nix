{
  programs.ssh = {
    enable = true;
    # includes = [];
    enableDefaultConfig = false;
    # extraOptionOverrides = {};

    matchBlocks = {
      # nixbuild = {
      #   checkHostIP = false;
      #   identitiesOnly = true;
      #   addKeysToAgent = "yes";
      #   host = "eu.nixbuild.net";
      #   serverAliveInterval = 60;
      #   hostname = "eu.nixbuild.net";
      #   identityFile = [ "~/.ssh/my-nixbuild-key" ];
      #   extraOptions = {
      #     PubkeyAcceptedKeyTypes = "ssh-ed25519";
      #     IPQoS = "throughput";
      #   };
      # };

      archlinux = {
        port = 22;
        user = "mfarabi";
        host = "archlinux";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "10.0.0.145";
        setEnv.TERM = "xterm-kitty";
      };

      macos = {
        port = 22;
        host = "macos";
        user = "mfarabi";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.50.151";
        setEnv.TERM = "xterm-kitty";
      };

      macos-intel = {
        port = 22;
        host = "macos-intel";
        user = "mfarabi";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.50.141";
        setEnv.TERM = "xterm-kitty";
      };

      freebsd = {
        port = 22;
        host = "freebsd";
        user = "mfarabi";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.50.142";
        setEnv.TERM = "xterm-kitty";
      };

      nixos = {
        port = 22;
        host = "nixos";
        user = "mfarabi";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.64.6";
        setEnv.TERM = "xterm-kitty";
      };

      nixos-server = {
        port = 22;
        user = "mfarabi";
        host = "nixos-server";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.50.254";
        setEnv.TERM = "xterm-kitty";
      };

      router = {
        port = 22;
        user = "admin";
        host = "router";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.50.1";
        setEnv.TERM = "xterm-256color";
      };

      rpi5 = {
        port = 22;
        host = "rpi5";
        user = "mfarabi";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "192.168.50.241";
        setEnv = {
          TERM = "xterm-256color";
        };

        # addressFamily = null; # "any" | "inet" | "inet6"
        # certificateFile = [ ./.file ];

        # compression = false;
        # controlmaster = null; # "yes" | "no" | "ask" | "auto" | "autoask"
        # controlPath = null; # path to control socket used for connection sharing
        # controlPersist = "10am"; # whether control socket should remain open in background

        # identityFile = [];
        # identityAgent = [];
        # identitiesOnly = false;

        # hashKnownHosts = null;
        # userKnownHostsFile = "~/.ssh/known_hosts";

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
