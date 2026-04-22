{
  pkgs,
  ...
}:
{
  programs.password-store = {
    enable = true;
    package = pkgs.pass.withExtensions (
      exts: with exts; [
        pass-otp
        pass-file
        # pass-tomb
        # pass-import # FIXME: "> dbus-daemon[20169]: Failed to start message bus: launchd's environment variable DBUS_LAUNCHD_SESSION_BUS_SOCKET is empty, but should contain a socket path."
        pass-update
        pass-checkup
        pass-genphrase
      ]
    );
    settings = {
      PASSWORD_STORE_DIR = "$HOME/.password-store";
    };
  };
}
