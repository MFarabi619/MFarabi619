{ lib, config, ... }:
{
  # process.manager.implementation = "process-compose";
  # process.manager.args = {
  #   shortcuts = "${config.git.root}/config/process-compose/shortcuts.yaml";
  #   theme     = "Monokai";
  # };
  process.managers.process-compose.settings.is_strict = true;

  processes = {
    # "cargo:loco:watch" = {
    #   exec = "cargo loco watch";
    #   ports.http.allocate = 5150;
    #   # process-compose = {
    #   #   is_tty = true;
    #   #   namespace = "🧩 API";
    #   # };
    # };
  }
  # //
  #   builtins.mapAttrs
  #     (_: cfg: {
  #       process-compose = {
  #         is_tty = true;
  #         namespace = "🎡 SERVICES";
  #       };
  #     })
  #     {
  #       sqld.enable = false;
  #       caddy.enable = true;
  #       mailpit.enable = true;
  #       prometheus.enable = false;
  #       "tailscale-funnel".enable = false;
  #     }
  // lib.optionalAttrs (!config.devenv.isTesting) {
    #   console = {
    #     exec = ''
    #       ttyd --writable --browser --url-arg --once devenv up
    #     '';
    #     process-compose = {
    #       disabled = true;
    #       namespace = "🧮 VIEWS";
    #       description = "🕹 Attach the Microvisor Kernel to the Browser";
    #     };
    # };
    # "test:firmware:qemu_riscv32" = {
    #   cwd = "${config.git.root}";
    #   exec = "west build apps/firmware --board qemu_riscv32 --build-dir build/qemu_riscv32_test --target run -DEXTRA_CONF_FILE=test.conf";
    # };
  };
}
