{ config, ... }:
{
  programs = {
    lazygit = {
      enable = true;
      settings = {
        disableStartupPopups = true;
        gui = {
          nerdFontsVersion = "3";
          parseEmoji = true;
          scrollPastBottom = true;
          scrollOffBehaviour = "jump";
          sidePanelWidth = 0.33;
          switchTabsWithPanelJumpKeys = true;
        };
        os = {
          edit = "emacsclient -n {{filename}}";
          editAtLine = "emacsclient -n +{{line}} {{filename}}";
          openDirInEditor = "emacsclient {{dir}}";
          editInTerminal = false;
        };
        git = {
          commit.signOff = true;
          branchPrefix = "${config.me.username}/";
        };
        promptToReturnFromSubprocess = true;
      };
    };
    };
}
