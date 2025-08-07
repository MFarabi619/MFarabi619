{
  # command-not-found handler to suggest nix way of installing stuff.
  # FIXME: This ought to show new nix cli commands though:
  # https://github.com/nix-community/nix-index/issues/191
  programs.nix-index = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
}
