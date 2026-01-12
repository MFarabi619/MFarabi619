{
  services.k3s = {
    enable = false;
    role = "server"; # Or "agent" for worker only nodes
    # clusterInit = true;
    extraFlags = toString [
      # "--debug" # Optionally add additional args to k3s
    ];
    # token = "<randomized common secret>";
    # serverAddr = "https://<ip of first node>:6443";
  };
}
