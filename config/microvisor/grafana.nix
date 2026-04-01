{
  pkgs,
  ...
}:
{
  packages = with pkgs; [
    grafana
    grafanactl
    mcp-grafana # https://github.com/grafana/mcp-grafana
  ];
}
