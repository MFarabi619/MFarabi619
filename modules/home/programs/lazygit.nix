{
  config,
  ...
}:
{
  programs.lazygit = {
    enable = true;
    enableZshIntegration = false; # NOTE: always drops you into root of monorepo otherwise
    settings = {
      notARepository = "quit";
      disableStartupPopups = true;
      promptToReturnFromSubprocess = true;

      gui = {
        sidePanelWidth = 0.33;
        nerdFontsVersion = "3";
        scrollPastBottom = false;
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
        overrideGpg = false;
        commit.signOff = true;
        branchPrefix = "${config.me.username}/";
        pagers = [
          {
            pager = "delta --paging=never";
          }
        ];
      };
    };
  };
}
