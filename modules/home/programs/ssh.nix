{
  programs.ssh = {
    enable = true;
    # includes = [];
    enableDefaultConfig = false;
    # extraOptionOverrides = {};

    matchBlocks = {
      nixbuild = {
        checkHostIP = false;
        identitiesOnly = true;
        addKeysToAgent = "yes";
        host = "eu.nixbuild.net";
        serverAliveInterval = 60;
        hostname = "eu.nixbuild.net";
        identityFile = [ "~/.ssh/my-nixbuild-key" ];
        extraOptions = {
          PubkeyAcceptedKeyTypes = "ssh-ed25519";
          IPQoS = "throughput";
        };
      };

      nixos-hetzner = {
        port = 22;
        user = "mfarabi";
        host = "nixos-hetzner";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "5.161.84.168";
        setEnv.TERM = "xterm-kitty";
      };

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
        hostname = "10.0.0.135";
        checkHostIP = true;
        addKeysToAgent = "yes";
        setEnv.TERM = "xterm-kitty";
      };

      freebsd = {
        port = 22;
        host = "freebsd";
        user = "mfarabi";
        hostname = "10.0.0.230";
        checkHostIP = true;
        addKeysToAgent = "yes";
        setEnv.TERM = "xterm-kitty";
      };

      nixos = {
        port = 22;
        host = "nixos";
        user = "mfarabi";
        hostname = "192.168.1.47";
        checkHostIP = true;
        addKeysToAgent = "yes";
        setEnv.TERM = "xterm-kitty";
      };

      rpi5 = {
        port = 22;
        host = "rpi5";
        user = "mfarabi";
        hostname = "10.0.0.29";

        checkHostIP = true;
        addKeysToAgent = "yes";

        setEnv.TERM = "xterm-kitty";
        # sendEnv = {};

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
