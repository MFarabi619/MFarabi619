{
  # system.stateVersion = "24.11";

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = "aarch64-linux";
  };

  systemd = {
    network.wait-online.enable = false;
    services = {
      # The notion of "online" is a broken concept
      # https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
      # https://github.com/NixOS/nixpkgs/issues/247608
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

  networking = {
    hostName = "rpi5";
    # Use networkd instead of the pile of shell scripts
    # NOTE: SK: is it safe to combine with NetworkManager on desktops?
    useNetworkd = true;
    # Keep dmesg/journalctl -k output readable by NOT logging
    # each refused connection on the open internet.
    firewall.logRefusedConnections = false;
  };

  services.udev.extraRules = ''
    # Ignore partitions with "Required Partition" GPT partition attribute
    # On our RPis this is firmware (/boot/firmware) partition
    ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
    ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
    ENV{UDISKS_IGNORE}="1"
  '';

}
