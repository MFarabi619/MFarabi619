{
  # config,
  ...
}:
{
  home.shellAliases.lg = "lazygit";
  programs.lazygit = {
    enable = true;
    settings = {
      notARepository = "skip";
      disableStartupPopups = true;
      promptToReturnFromSubprocess = true;

      gui = {
        sidePanelWidth = 0.33;
        nerdFontsVersion = "3";
        scrollPastBottom = true;
        scrollOffBehaviour = "jump";
        switchTabsWithPanelJumpKeys = true;
      };

      os = {
        editInTerminal = true;
        edit = "emacsclient -nw {{filename}}";
        openDirInEditor = "emacsclient -nw {{dir}}";
        editAtLine = "emacsclient -nw +{{line}} {{filename}}";
      };

      git = {
        parseEmoji = true;
        commit.signOff = true;
        branchPrefix = "mfarabi/";
        # branchPrefix = "${config.me.username}/";
      };
    };
  };
}
