{
  # config,
  ...
}:
{
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
        edit = "emacs -nw {{filename}}";
        openDirInEditor = "emacs -nw {{dir}}";
        editAtLine = "emacs -nw +{{line}} {{filename}}";
      };

      git = {
        parseEmoji = true;
        overrideGpg = true;
        commit.signOff = true;
        branchPrefix = "mfarabi/";
        # branchPrefix = "${config.me.username}/";
      };
    };
  };
}
