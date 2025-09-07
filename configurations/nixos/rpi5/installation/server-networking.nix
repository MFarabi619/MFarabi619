{ lib, ... }:
{
  # https://github.com/nix-community/srvos/blob/fa814c65868d32f7bd4d13a87b191ace02feb7d8/nixos/common/networking.nix
  # with some options disabled
  networking = {
    hostname = "rpi5";
    firewall = {
      # Keep dmesg/journalctl -k output readable by NOT logging
      # each refused connection on the open internet.
      logRefusedConnections = lib.mkDefault false;
      nallowPing = true; # Allow PMTU / DHCP
    };
    # Use networkd instead of the pile of shell scripts
    # NOTE: SK: is it safe to combine with NetworkManager on desktops?
    useNetworkd = lib.mkDefault true;
  };

  # The notion of "online" is a broken concept
  # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
  # https://github.com/NixOS/nixpkgs/issues/247608
  systemd = {
    network.wait-online.enable = false;
    services = {
      NetworkManager-wait-online.enable = false;
      # Do not take down the network for too long when upgrading,
      # This also prevents failures of services that are restarted instead of stopped.
      # It will use `systemctl restart` rather than stopping it with `systemctl stop`
      # followed by a delayed `systemctl start`.
      systemd-networkd.stopIfChanged = false;
      # Services that are only restarted might be not able to resolve when resolved is stopped before
      systemd-resolved.stopIfChanged = false;
    };
  };
}
