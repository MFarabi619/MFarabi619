{
  programs.ssh = {
    enable = true;
    # includes = [];
    enableDefaultConfig = false;
    # extraOptionOverrides = {};
    settings = {
      "*" = {
        checkHostIP = true;
        addKeysToAgent = "yes";
        controlMaster = "auto";
        controlPersist = "10m";
        controlPath = "~/.ssh/cm-%C";
        CanonicalizeHostname = "yes";
        ExitOnForwardFailure = "yes";
        SetEnv.TERM = "xterm-256color";
        CanonicalDomains = "taila4d019.ts.net";
      };
    }
    // {
      "rpi02w rpi02w-* rutx11 halowlink2-* halowlink1-3c5b rut241" = {
        user = "root";
      };
      "rt-be88u-7a50" = {
        user = "admin";
      };
      "framework-* rpi* ubuntu msi-* macbook-* macos nixos-wsl surface-pro-7 hp-elitebook-820-g2 guix nixos-utm ubuntu-s-1vcpu-512mb-10gb-tor1-01" =
        {
          user = "mfarabi";
        };
    }
    // {
      "framework-desktop macbook-11-4 macos msi-gs76 nixos-wsl surface-pro-7 hp-elitebook-820-g2 nixos-utm" =
        {
          SetEnv.TERM = "xterm-kitty";
        };
    }
    // {
      "guix" = {
        hostname = "macbook-5-5";
      };
      "ubuntu-s-1vcpu-512mb-10gb-tor1-01" = {
        hostname = "ubuntu-s-1vcpu-512mb-10gb-tor1-01";
      };
    }
    // {
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
      # match = ''
      #   host canonical
      #   host exec "ping -c1 -q 192.168.17.1"
      # '';
      # dynamicForwards = [
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
}
