# dotfiles
A collection of my dotfile configurations used across different operating systems.

## MacOS/Unix
A collection of my dotfile configurations used for MacOs/Unix, tailored for a windows-like experience.

[Terminal Setup for Mac](https://www.youtube.com/watch?v=CF1tMjvHDRA&t=46s&ab_channel=JoseanMartinez)

[How To Use A Tiling Window Manager On MacOs | Yabai Ultimate Guide](https://www.youtube.com/watch?v=k94qImbFKWE)

[7 Amazing CLI Tools You Need To Try](https://www.youtube.com/watch?v=mmqDYw9C30I&t=721s)

Install [Homebrew](https://brew.sh/) for easy package installation
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# After installation is complete, run the commands that Homebrew tells you run in the Next steps section.
```

Install [iTerm2](https://iterm2.com/) to use as default terminal
```bash
brew install --cask iterm2
```

Install [Git](https://git-scm.com/) for version control
```bash
brew install git
```

Install [Zsh](https://zsh.sourceforge.io/) to use as default
```bash
brew install zsh
```

Install [Oh My Zsh](https://ohmyz.sh/), a framework to easily customize the look and feel of zsh
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Install [PowerLevel10K Theme for Oh My Zsh](https://github.com/romkatv/powerlevel10k), a theming system for the Oh My Zsh framework
```bash
git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
```

Open `~/.zshrc` and change the the value of `ZSH_THEME`:
```bash
ZSH_THEME="powerlevel10k/powerlevel10k
```

Source `.zshrc`:
```bash
source ~/.zshrc
```

Configure PowerLevel10K
```bash
p10k configure
```

#### Install ZSH Plugins
Install zsh-autosuggestions:
```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

Install zsh-syntax-highlighting:
```bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

Open `~/.zshrc` and modify the plugins line:
```bash
plugins=(git zsh-autosuggestions zsh-syntax-highlighting web-search)
```

Source zsh again:
```bash
source ~/.zshrc
```

Install GNU Stow:
```bash
sudo apt-get install stow
```

Navigate to dotfiles directory and run stow to create symlinks:
```bash
cd ~/dotfiles
stow .
```

## Mouse setup

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/a1a5e18b-1c3b-4708-9be2-4a3dc886a8b9)


<details>
<summary>
<h2>If using Karabiner (Don't use it, it bugged out for me from time to time)</h2>
</summary>
<h3>
  
Here's a [config file](https://ke-complex-modifications.pqrs.org/#pc_shortcuts) for Mac to Windows keyboard mappings

</h3>

```bash
brew install --cask karabiner-elements
```
<h3>
  Re-map caps lock to ctrl
</h3>

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/93f379ae-d2ac-4b08-a531-33d4fd226379)

### Delete the `ctrl+tab -> alt+tab` mapping so that it doesn't conflict with AltTab

</details>
<details>
<summary><h2>If not using Karabiner</h2></summary>
<h3>  
Re-map modifier keys for external keyboard
</h3>

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/27127400-06bf-49c9-92f7-ae9e2563865b)
<h3>
Re-map modifier keys for Apple Internal Keyboard
</h3>

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/37bab098-baf7-408a-8899-aeb1c54994bc)
<h3>  
BetterTouchTool
</h3> 

```bash
brew install --cask bettertouchtool
```

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/0710fc72-778e-4cf2-9634-a4b188990441)

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/9cb029b5-db83-4c26-b03f-3ee0351d7bba)


</details>


## [SurfingKeys](https://chromewebstore.google.com/detail/surfingkeys/gfbliohnnapiefjpjlpjnehglfpaknnc?pli=1) for browser

## [DisplayLink](https://www.synaptics.com/products/displaylink-graphics/downloads/macos) for triple/multi-monitor setup with [StarTech dock](https://www.amazon.ca/Triple-Display-Docking-Station-Universal/dp/B012VKW900/ref=asc_df_B012VKW900/?tag=googleshopc0c-20&linkCode=df0&hvadid=293004044609&hvpos=&hvnetw=g&hvrand=8700524289148619145&hvpone=&hvptwo=&hvqmt=&hvdev=c&hvdvcmdl=&hvlocint=&hvlocphy=9000694&hvtargid=pla-349910448191&mcid=3cd8b0ad72503a5b9e6b12a41cafff96&th=1)
```bash
brew install --cask displaylink
```

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/be887f39-0dd2-4ebd-aa41-5ca444cf3425)

## [MonitorControl](https://formulae.brew.sh/cask/monitorcontrol) for adjusting brightness across Monitors.
```bash
brew install --cask monitorcontrol
```

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/04195e2d-8860-4c6d-8e92-c3c3364c6741)
![image](https://github.com/MFarabi619/dotfiles/assets/54924158/b30e6994-61ec-410f-b65a-980dd8c71291)


## [AltTab](https://alt-tab-macos.netlify.app/) to switch between windows
```bash
brew install --cask alt-tab
```

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/937040c0-3129-419d-a61d-9180302437a2)
![image](https://github.com/MFarabi619/dotfiles/assets/54924158/66bc62b4-f6d4-4664-87dd-8a5ef8430727)
![image](https://github.com/MFarabi619/dotfiles/assets/54924158/f0ab830c-c53c-4082-9f1a-0d3c9ab574cf)


## Settings
## Adjust display brightness using keyboard
![image](https://github.com/MFarabi619/dotfiles/assets/54924158/ec6f256d-2cca-4979-95bb-310616400a56)

## Screenshot with cmd+shift+s

![image](https://github.com/MFarabi619/dotfiles/assets/54924158/09ce8880-d11a-45f3-85c7-c4d691f4ec55)

## Install [NeoVim](https://neovim.io/)

```bash
brew install neovim
```

## Install [LazyVim](https://www.lazyvim.org/)

Before installing LazyVim, install its required dependencies.

[LazyGit](https://github.com/jesseduffield/lazygit)

```bash
brew install lazygit
```

[ripgrep](https://github.com/BurntSushi/ripgrep)

```bash
brew install ripgrep
```

[fd](https://github.com/sharkdp/fd)

```bash
brew install fd
```

```bash
# Make a backup of your current Neovim files:
# required
mv ~/.config/nvim{,.bak}

# optional but recommended
mv ~/.local/share/nvim{,.bak}
mv ~/.local/state/nvim{,.bak}
mv ~/.cache/nvim{,.bak}

# Clone the starter
git clone https://github.com/LazyVim/starter ~/.config/nvim

# Remove the .git folder, so you can add it to your own repo later
rm -rf ~/.config/nvim/.git

# Start LazyVim and run `:LazyHealth`
nvim
```

TODO: Look at what else needs to be added and add them
![image](https://github.com/MFarabi619/dotfiles/assets/54924158/fb4299c4-64a2-4f10-864f-50480de0156e)

