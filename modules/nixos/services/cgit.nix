{
  pkgs,
  flake,
  ...
}:
{
  services.cgit."cgit" = {
    enable = true;
    scanPath = "/var/lib/git";
    gitHttpBackend.enable = true;

    repos = {
      MFarabi619 = {
        path = "/var/lib/git/MFarabi619";
        desc = "Monorepo containing configs, projects, notes, etc. Doubling as practice for managing huge, multi-language codebases with potentially unrelated concerns.";
      };
    };

    settings = {
      root-title = "Mumtahin Farabi";
      root-desc = "A society grows great when the old plant trees in whose shade they know they shall never sit. 🌴";

      remove-suffix = "1";
      section-from-path = "1";

      enable-git-config = "1";
      enable-http-clone = "1";
      enable-html-serving = "1";
      enable-index-links = "1";
      enable-index-owner = "0";

      enable-log-filecount = "1";
      enable-log-linecount = "1";
      enable-remote-branches = "1";
      enable-subject-links = "1";
      enable-tree-linenumbers = "1";

      enable-blame = "1";
      enable-commit-graph = "1";
      enable-filter-overrides = "1";

      branch-sort = "age";

      favicon = "${flake.self}/assets/apollyon-linux-logo.png";
      logo-link = "https://mfarabi.sh";

      snapshots = "tar.gz";

      readme = [
        ":README.md"
        ":README"
        ":readme.md"
        ":readme"
      ];

      cache-size = "1000";
      cache-root = "/var/cache/cgit";

      about-filter = "${pkgs.cgit}/lib/cgit/filters/about-formatting.sh";

      css = [
        "/etc/cgit.css"
        "${flake.self}/assets/gruvbox.cgit.css"
      ];
    };
  };
}
