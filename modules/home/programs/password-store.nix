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
      ]
    );
    settings = {
      PASSWORD_STORE_DIR = "$HOME/.password-store";
    };
  };
}
