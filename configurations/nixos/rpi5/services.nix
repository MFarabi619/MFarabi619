{
  services = {
    # auto login at virtual console
    getty.autologinUser = "mfarabi";
    udev = {
      enable = true;
      extraRules = ''
        # Ignore partitions with "Required Partition" GPT partition attribute
        # On our RPis this is firmware (/boot/firmware) partition
        ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
        ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
        ENV{UDISKS_IGNORE}="1"
      '';
    };
  };
}
