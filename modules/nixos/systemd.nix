{
  pkgs,
  ...
}:
{
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      description = "polkit-gnome-authentication-agent-1";
      serviceConfig = {
        RestartSec = 1;
        Type = "simple";
        TimeoutStopSec = 10;
        Restart = "on-failure";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      };
    };
}
