{
  programs.ssh = {
    enable = true;
    # includes = [];
    enableDefaultConfig = false;
    # extraOptionOverrides = {};

    matchBlocks = {
      RT-BE88U-7A50 = {
        user = "admin";
        host = "RT-BE88U-7A50";
        addKeysToAgent = "yes";
        hostname = "rt-be88u-7a50.taila4d019.ts.net";
        setEnv.TERM = "xterm-256color";
      };

      hp-elitebook-820-g2 = {
        user = "mfarabi";
        host = "hp-elitebook-820-g2";
        addKeysToAgent = "yes";
        hostname = "hp-elitebook-820-g2.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      macbook-5-5 = {
        host = "guix";
        user = "mfarabi";
        addKeysToAgent = "yes";
        hostname = "macbook-5-5.taila4d019.ts.net";
        setEnv.TERM = "xterm-256color";
      };

      macbook-11-4 = {
        user = "mfarabi";
        host = "macbook-11-4";
        addKeysToAgent = "yes";
        hostname = "macbook-11-4.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      macbook-16-5 = {
        host = "macos";
        user = "mfarabi";
        addKeysToAgent = "yes";
        hostname = "macbook-16-5.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      msi-gs65 = {
        user = "mfarabi";
        host = "msi-gs65";
        addKeysToAgent = "yes";
        hostname = "msi-gs65.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      msi-gs76 = {
        host = "msi-gs76";
        user = "mfarabi";
        addKeysToAgent = "yes";
        hostname = "msi-gs76.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      framework-16 = {
        user = "mfarabi";
        host = "framework-16";
        addKeysToAgent = "yes";
        hostname = "framework-16.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      framework-desktop = {
        user = "mfarabi";
        host = "framework-desktop";
        addKeysToAgent = "yes";
        hostname = "nixos-server.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      surface-pro-7 = {
        user = "mfarabi";
        host = "surface-pro-7";
        addKeysToAgent = "yes";
        hostname = "surface-pro-7.taila4d019.ts.net";
        setEnv.TERM = "xterm-kitty";
      };

      rpi5-16 = {
        host = "rpi5-16";
        user = "mfarabi";
        checkHostIP = true;
        addKeysToAgent = "yes";
        hostname = "rpi5-16.taila4d019.ts.net";
        setEnv.TERM = "xterm-256color";
        };

      rpi5-4 = {
        host = "rpi5-4";
        user = "mfarabi";
        addKeysToAgent = "yes";
        hostname = "rpi5-4.taila4d019.ts.net";
        setEnv.TERM = "xterm-256color";
      };

      rpi5-8 = {
        host = "rpi5-8";
        user = "mfarabi";
        addKeysToAgent = "yes";
        hostname = "rpi5-8.taila4d019.ts.net";
        setEnv.TERM = "xterm-256color";
      };

      ubuntu-s-1vcpu-1gb-50gb-mon1-01 = {
        user = "ubuntu";
        addKeysToAgent = "yes";
        host = "ubuntu-s-1vcpu-1gb-50gb-mon1-01";
        hostname = "ubuntu-s-1vcpu-1gb-50gb-mon1-01.taila4d019.ts.net";
        setEnv.TERM = "xterm-256color";
      };

      ubuntu-s-1vcpu-512mb-10gb-tor1-01 = {
        user = "mfarabi";
        addKeysToAgent = "yes";
        host = "ubuntu-s-1vcpu-512mb-10gb-tor1-01.taila4d019.ts.net";
        hostname = "ubuntu-s-1vcpu-512mb-10gb-tor1-01";
        setEnv.TERM = "xterm-256color";

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
