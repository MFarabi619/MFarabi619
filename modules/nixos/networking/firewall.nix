{
  lib,
  config,
  ...
}:

{
  networking.firewall = {
    enable = true;

    allowedUDPPorts = [
      68
      546
    ]
    ++
      lib.optionals
        (builtins.elem config.networking.hostName [
          "nixos-vm"
        ])
        [
          59010
          59011
        ]
    ++ lib.optionals config.services.k3s.enable [
      # 8472 # flannel: required if using multi-node for inter-node networking
    ];

    allowedTCPPorts =
      lib.optionals
        (builtins.elem config.networking.hostName [
          "nixos-vm"
        ])
        [
          80
          443
          8080
          59010
          59011
        ]
      ++ lib.optionals config.services.k3s.enable [
        6443 # required so that pods can reach the API server (running on port 6443 by default)
        # 2379 # etcd clients: required if using a "High Availability Embedded etcd" configuration
        # 2380 # etcd peers: required if using a "High Availability Embedded etcd" configuration
      ];
  };
}
