{
  programs.radicle = {
    enable = true;
    uri.rad.browser = true;
    uri.web-rad.enable = true;
    uri.rad.vscode.enable = true;
    settings = {
      node.alias = "mfarabi";
      web.pinned.repositories = [ "rad:z2VXjpUYKv3CN6DzjZS983Bo3qo7d" ];
      web.avatarUrl = "https://avatars.githubusercontent.com/u/54924158?v=4";
      # web.bannerUrl = "https://your-image-url.com/banner.png";
      web.description = "A society grows great when the old plant trees in whose shade they know they shall never sit. 🌴";
    };
  };
}
