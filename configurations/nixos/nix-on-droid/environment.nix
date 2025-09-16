{ pkgs, ... }:
{
  environment = {
    # Backup etc files instead of failing to activate generation if a file already exists in /etc
    etcBackupExtension = ".bak";

    packages = with pkgs; [
      man
      xz
      zip
      sudo
      gzip
      unzip
      gnupg
      bzip2
      gnused
      gnutar
      tzdata
      procps
      killall
      openssh
      gnugrep
      hostname
      diffutils
      findutils
      utillinux

      devenv
    ];
  };
}
