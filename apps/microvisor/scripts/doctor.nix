{ pkgs, ... }:

{
  scripts = {
    doctor = {
      description = " 💊 Run Microdoctor health-check suite with docs output";
      exec = ''
        figlet -cf slant "💊 Microdoctor";
        ${pkgs.shellspec}/bin/shellspec -c microvisor/env --quiet "$@";
      '';
    };
  };
}
