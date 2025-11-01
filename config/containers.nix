{
  containers = {
    microvisor = {
      maxLayers = 1;
      version = "latest";
      # layers = [ ];
      # copyToRoot = [ ];
      # entrypoint = [];
      startupCommand = null;
      # defaultCopyArgs = [ ];
      registry = "docker-daemon:";
      enableLayerDeduplication = true;
    };
  };
}
