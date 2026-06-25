{
  config,
  pkgs,
  ...
}:
{
  scripts = {
    up.exec = ''devenv up "$@"'';
    clean.exec = "git clean -fdX";
    run.exec = ''devenv tasks run "$@" -m before'';
    docs.exec = "bunx likec4 start ${config.git.root}/docs";
    tio.exec = ''HOME="$DEVENV_ROOT" ${pkgs.tio}/bin/tio "$@"'';
    "emulate:firmware".exec = ''
      west build apps/firmware --board qemu_riscv32 --build-dir build/qemu_riscv32 --target run
    '';
  };
}
