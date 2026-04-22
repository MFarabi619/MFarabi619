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
        pass-update
      ]
    );
    settings = {
      PASSWORD_STORE_DIR = "$HOME/.password-store";
    };
  };
}
