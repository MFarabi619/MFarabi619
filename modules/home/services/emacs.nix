{
  config,
  ...
}:
{
  services.emacs = rec {
    enable = config.programs.emacs.enable;
    # socketActivation.enable = true;
    defaultEditor = false;
    # extraOptions = [ "TERM=xterm-kitty" ];

    client = {
      inherit enable;
      # arguments = [
      #   "--tty"
      # ];
    };
  };
}
