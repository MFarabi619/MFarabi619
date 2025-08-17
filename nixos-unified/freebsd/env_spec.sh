figlet -cf slant "🐚 FreeBSD Hyprland"

# fastfetch -c all.jsonc

Describe "📦 System Package Installation"
It "should have git, zsh, lazygit, etc. installed"
When run which git && which zsh && which lazygit
The status should be success
End
End

Describe "🛠 Zsh Environment"
It "should use powerlevel10k theme"
When run grep '^ZSH_THEME="powerlevel10k/powerlevel10k"' ~/.zshrc
The status should be success
End

It "should include expected plugins"
When run grep '^plugins=(.*zsh-autosuggestions.*zsh-syntax-highlighting.*)' ~/.zshrc
The status should be success
End
End

Describe "🖥 Terminal Utilities"
It "should include tools like eza, fzf, bat, etc."
When run which eza && which fzf && which bat && which fd
The status should be success
End
End

Describe "📋 Dev Utilities"
It "should have docker and docker-compose installed"
When run which docker && which docker-compose
The status should be success
End

It "docker should be working"
When run docker info
The status should be success
The output should not include 'ERROR'
End
End

Describe "🧠 Fun CLI Tools"
Parameters
"btop" "fastfetch" "cmatrix" "cowsay" "asciiquarium" "lolcat"
End

Example "$1"
When run which $1
The status should be success
End
End

Describe "🖊 Editor Setup"
It "should have neovim and emacs"
When run which nvim && which emacs
The status should be success
End

It "should have LazyVim and DoomEmacs installed"
When run test -d ~/.config/nvim && test -d ~/.config/emacs
The status should be success
End
End

Describe "🌐 Node/NPM Environment"
It "should have npm installed"
When run which npm
The status should be success
End
End

Describe "🖼 Hyprland Environment"
It "should have hyprland and required tools installed"
When run which hyprland && which waybar && which wl-clipboard
The status should be success
End

It "should have proper group membership"
When run groups
The output should include 'video'
End

It "should detect DRM device"
When run ls /dev/dri/card0
The status should be success
End
End

Describe "🔑 /etc/rc.conf Configuration"
It "should enable seatd, dbus, and i915kms"
When run grep -E 'seatd_enable="YES"|dbus_enable="YES"|kld_list=".*i915kms.*"' /etc/rc.conf
The status should be success
End
End

Describe "📡 SSH Daemon Config"
It "should allow pubkey auth"
When run grep '^PubkeyAuthentication yes' /etc/ssh/sshd_config
The status should be success
End
End

Describe "🔧 DRM Driver Initialization"
It "should have i915 loaded"
When run dmesg | grep i915
The output should include 'drm' # Could be more specific based on your hardware
End
End

Describe "🧪 Basic Commands Should Exist"
Parameters
"tree" "ripgrep" "smartctl" "s-tui" "symon"
End

Example "$1"
When run which $1
The status should be success
End
End
