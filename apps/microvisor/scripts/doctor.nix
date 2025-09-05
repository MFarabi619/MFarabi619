{ pkgs, config, ... }:
{
  files = {
    ".shellspec" = {
      text = "";
    };
  };

  scripts = {
    doctor = {
      packages = with pkgs; [figlet shellspec];
      description = " 💊 Run Microdoctor health-check suite with docs output";
      exec = ''
        figlet -cf slant "💊 Microdoctor";
        shellspec -c "${config.env.DEVENV_ROOT}/apps/microvisor/env" --quiet "$@";
      '';
    };
  };
}
