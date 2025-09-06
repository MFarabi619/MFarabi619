{
  networking.firewall = {
    allowedTCPPorts = [
      6443 # required so that pods can reach the API server (running on port 6443 by default)
      # 2379 # etcd clients: required if using a "High Availability Embedded etcd" configuration
      # 2380 # etcd peers: required if using a "High Availability Embedded etcd" configuration
    ];
    allowedUDPPorts = [
      # 8472 # flannel: required if using multi-node for inter-node networking
    ];
  };
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
