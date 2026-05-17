{
  config,
  ...
}:
{
  services.emacs = {
    enable = config.programs.emacs.enable;
    defaultEditor = false;
    # socketActivation.enable = true;

    # extraOptions = [
    #   "TERM=xterm-kitty"
    # ];

    # client = {
    #   enable = true;
    #   # arguments = [
    #   #   "--tty"
    #   # ];
    # };
  };
}
