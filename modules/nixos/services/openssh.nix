{
  lib,
  pkgs,
  ...
}:
{
  services.openssh = {
    enable = true;
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    settings = {
      PermitRootLogin = "yes";
    };
  };
}
