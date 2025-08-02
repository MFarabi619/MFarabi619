# This is your nixos configuration.
# For home configuration, see /modules/home/*
{ flake, ... }:
{
  imports = [
    flake.inputs.self.nixosModules.common
  ];

security = {
  rtkit.enable = true;
};

  services = {
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
      };
      pulse.enable = true;
      jack.enable = true;
    };
    openssh.enable = true;
    # cachix-watch-store = {
    #   enable = true;
    #   verbose = true;
    #   # host = "";
    #   cacheName = "charthouse-labs";
    #   # jobs = 12;
    #   # compressionLevel = 0;
    #   cachixTokenFile = ../../cachixTokenFile;
    #   # signingKeyFile = "";
    # };
    hercules-ci-agent = {
      enable = true;
      settings = {
      concurrentTasks = 4;
      #   baseDirectory = "";
      #   binaryCachesPath = "";
      #   clusterJoinTokenPath = "";
      #   labels = "";
      #   workDirectory = "";
      #   apiBaseUrl = "";
        };
        };
  };
}
