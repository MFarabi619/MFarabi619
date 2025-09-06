{
  programs = {
    gh = {
      enable = true;
      settings = {
        git_protocol = "https";
        # aliases = {
        #  co = "pr checkout";
        #  pv = "pr view";
        # };
        # editor = ""
      };
      # hosts = {
      #   "github.com" = {
      #     user = "MFarabi619";
      #   };
      # };
  #     gitCredentialHelper = {
  #      enable = true;
  #      hosts = [
  #        "https://github.com"
  # "https://gist.github.com"
  #      ];
  #     };
      # extensions = with pkgs; [];
    };
    gh-dash = {
      enable = true;
      # settings = {};
    };
  };
}
