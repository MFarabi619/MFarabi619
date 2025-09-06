{
  nixpkgs = {
    # buildPlatform = "aarch64-darwin";
    hostPlatform = "aarch64-darwin";
    config = {
      allowUnfree = true;
    };
  };
}
