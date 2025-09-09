{ lib, ... }:
{
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  # no longer valid

  services.udev.extraRules = ''
    ATTR{address}=="92:00:06:74:db:01", NAME="eth0"
    ATTR{address}=="86:00:00:a4:ea:0c", NAME="enp7s0"
  '';

  networking = {
    dhcpcd.enable = false;
    defaultGateway = "172.31.1.1";
    nameservers = [
      "8.8.8.8"
    ];
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4 = {
          addresses = [
            {
              address = "5.161.84.168";
              prefixLength = 32;
            }
          ];
          routes = [
            {
              address = "172.31.1.1";
              prefixLength = 32;
            }
          ];
        };
        ipv6 = {
          addresses = [
            {
              address = "2a01:4ff:f0:fd02::1";
              prefixLength = 64;
            }
            {
              address = "fe80::9000:6ff:fe74:db01";
              prefixLength = 64;
            }
          ];
          routes = [
            {
              address = "fe80::1";
              prefixLength = 128;
            }
          ];
        };
      };
      enp7s0 = {
        ipv4.addresses = [
          {
            address = "10.0.0.2";
            prefixLength = 32;
          }
        ];
        ipv6.addresses = [
          {
            address = "fe80::8400:ff:fea4:ea0c";
            prefixLength = 64;
          }
        ];
      };
    };
  };
}
