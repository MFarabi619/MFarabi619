# {
#   config,
#   ...
# }:
{
  services.plantuml-server = {
    # enable = builtins.elem config.networking.hostName [
    #   "framework-desktop"
    #   "nixos-server"
    # ];
  };
}
