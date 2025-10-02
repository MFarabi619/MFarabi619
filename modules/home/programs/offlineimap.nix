{
  programs.offlineimap = {
    enable = true;
    # pythonFile = ''
    #   import subprocess

    #   def get_pass(service, cmd):
    #       return subprocess.check_output(cmd, )
    # '';
    extraConfig = {
     # default = {
     #   gmailtrashfolder = "[Gmail]/Papierkorb";
     # };
     # general = {
     #   maxage = 30;
     #   ui = "blinkedlights";
     # };
     # mbnames = {
     #   filename = "~/.config/mutt/mailboxes";
     #   header = "'mailboxes '";
     #   peritem = "'+%(accountname)s/%(foldername)s'";
     #   sep = "' '";
     #   footer = "'\\n'";
     # };
    };
  };
}
