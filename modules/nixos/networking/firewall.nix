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
        ];

    allowedTCPPorts = [
    ]
    ++ lib.optionals config.services.openssh.enable [
      22
    ]
    ++ lib.optionals config.services.netdata.enable [
      19999
    ]
    ++
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
        ];
  };
}
