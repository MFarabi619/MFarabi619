{
  config,
  ...
}:
{
  services.sqld = {
    enable = true;
    extraArgs = [
      "--enable-http-console"
      "--db-path=${config.git.root}/config/data.sqld"
    ];
  };
}
