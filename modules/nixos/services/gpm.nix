{
  # general purpose mouse daemon, enable mouse support in virtual consoles
  services.gpm = {
   enable = true;
    protocol = "ps/2";
  };
}
