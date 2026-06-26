{
  config,
  ...
}:
{
  services.emacs = {
    enable = config.programs.emacs.enable;
    # socketActivation.enable = true;
    defaultEditor = false;
    # extraOptions = [ "TERM=xterm-kitty" ];


    # client = {
    #   enable = true;
    #   # arguments = [
    #   #   "--tty"
    #   # ];
    # };
  };
}
