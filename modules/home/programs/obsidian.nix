{
  programs.obsidian = {
    enable = false;
    vaults = { };

    defaultSettings = {
      app = { };
      appearance = { };
      hotkeys = { };
      themes = [ ];
      extraFiles = { };
      cssSnippets = [ ];
      communityPlugins = [ ];

      corePlugins = [
        "graph"
        "canvas"
        "slides"
        "publish"
        "outline"
        "backlink"
        "switcher"
        "tag-pane"
        "bookmarks"
        "templates"
        "word-count"
        "properties"
        "workspaces"
        "random-note"
        "daily-notes"
        "page-preview"
        "editor-status"
        "file-explorer"
        "file-recovery"
        "global-search"
        "slash-command"
        "note-composer"
        "outgoing-link"
        "command-palette"
        "markdown-importer"
      ];
    };
  };
}
