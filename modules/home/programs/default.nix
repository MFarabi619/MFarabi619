{
  imports =
    with builtins;
    let
      exclude = [
        "default.nix"
        "surfingkeys"
      ];
    in
    map (fn: ./${fn}) (filter (fn: !(elem fn exclude)) (attrNames (readDir ./.)));
}
# {
#   imports = [
#     ./neovim
#     ./emacs
#     ./vivaldi
#     ./zsh

#     ./anki.nix
#     ./aria2.nix
#     ./aria2p.nix
#     ./atuin.nix
#     ./aichat.nix

#     ./bash.nix
#     ./bat.nix
#     ./btop.nix
#     ./bun.nix

#     ./cargo.nix
#     ./chromium.nix
#     ./clock-rs.nix
#     ./command-not-found.nix

#     ./direnv.nix
#     ./delta.nix

#     ./element-desktop.nix
#     ./eza.nix

#     ./fastfetch
#     ./fd.nix
#     # ./firefox.nix
#     ./fzf.nix

#     ./gcc.nix
#     ./gh.nix
#     ./git.nix
#     ./go.nix
#     ./gpg.nix
#     ./grep.nix

#     ./home-manager.nix
#     ./hyprland

#     ./info.nix
#     ./jq.nix
#     ./jqp.nix
#     ./k9s.nix
#     ./kitty
#     ./kubecolor.nix
#     ./lazydocker.nix
#     ./lazygit.nix
#     ./lazysql.nix
#     ./less.nix
#     ./lutris.nix
#     ./man.nix
#     ./msmtp.nix
#     ./mbsync.nix
#     ./mcp.nix
#     ./mpv.nix
#     ./mu.nix

#     ./nh.nix
#     ./npm.nix
#     ./neomutt.nix
#     ./nix-index.nix
#     ./nix-search-tv.nix
#     ./nix-your-shell.nix

#     ./obs-studio.nix
#     ./obsidian.nix
#     ./opencode.nix
#     ./openstackclient.nix
#     ./password-store.nix
#     ./pandoc.nix
#     ./rbw.nix
#     ./ripgrep.nix
#     ./ripgrep-all.nix
#     ./rtorrent.nix
#     ./ruff.nix
#     ./ssh.nix
#     ./sftpman.nix
#     ./sqls.nix
#     ./sketchybar
#     ./starship
#     ./television.nix
#     ./tex-fmt.nix
#     ./texlive.nix
#     ./tiny.nix
#     ./tmux.nix
#     ./uv.nix
#     ./vim.nix
#     ./vscode.nix
#     ./yazi.nix
#     ./zed-editor.nix
#     ./zellij.nix
#     ./zoxide.nix
#   ];
# }
