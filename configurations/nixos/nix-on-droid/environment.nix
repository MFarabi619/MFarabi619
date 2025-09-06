{ pkgs, ... }:
{
  environment = {
    packages = with pkgs; [
      sudo
      devenv

      openssh

      procps
      killall
      diffutils
      findutils
      utillinux
      tzdata
      hostname
      man
      gnugrep
      gnupg
      gnused
      gnutar
      bzip2
      gzip
      xz
      zip
      unzip
    ];
    # Backup etc files instead of failing to activate generation if a file already exists in /etc
    etcBackupExtension = ".bak";

    sessionVariables = {
      EDITOR = "nvim";
    };
  };
}
