{
  services.hercules-ci-agent = {
    enable = false;
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
}
