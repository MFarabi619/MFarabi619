{
  lib,
  pkgs,
  config,
  ...
}:
{
  services.openssh = {
    enable = true;
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    settings = {
      PermitRootLogin = "yes";
    }
    // lib.optionalAttrs config.services.proxmox-ve.enable {
      AcceptEnv = lib.mkForce [
        "TERM"
        "LANG"
        "LC_*"
      ];
    };
  };
}
