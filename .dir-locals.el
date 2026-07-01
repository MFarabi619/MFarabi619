;; Copyright (C) 2022-2025 Free Software Foundation, Inc.

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

((nil .
      ((compile-multi-dir-local-config
        . ((t
            ;; ======================================|========|===============================================|=========|===========================|===========|============ ;;
            ("󱄅 flake  :󰔡 activate"                  :command "nix run .#activate"                                                                 :annotation "       nix ")
            ;; ======================================|========|===============================================|=========|===========================|===========|============ ;;
            ("󱄅 devenv  :󰋽 info"                     :command "devenv info"                                  :prodigy t                            :annotation "       nix 󱄅")
            ("󱄅 devenv  :󰇺 tasks"                    :command "devenv tasks list"                            :prodigy t                            :annotation "       nix 󱄅")
            ("󱄅 devenv  :󰚦 down"                     :command "devenv processes down"                        :prodigy t                            :annotation "       nix 󱄅")
            ("󱄅 devenv  : sqld"                     :command "devenv up sqld"                               :prodigy t :port 8080                 :annotation "       nix 󱄅")
            ("󱄅 devenv  : caddy"                    :command "devenv up caddy"                              :prodigy t :port   80                 :annotation "       nix 󱄅")
            ("󱄅 devenv  :󰇮 mailpit"                  :command "devenv up mailpit"                            :prodigy t :port 8025                 :annotation "       nix 󱄅")
            ("󱄅 devenv  : postgres"                 :command "devenv up postgres"                           :prodigy t :port 5432                 :annotation "       nix 󱄅")
            ("󱄅 devenv  : tailscale"                :command "devenv up tailscale"                          :prodigy t :port 8080                 :annotation "       nix 󱄅")
            ("󱄅 devenv  : prometheus"               :command "devenv up prometheus"                         :prodigy t :port 9090                 :annotation "       nix 󱄅")
            ;; ======================================|========|===============================================|=========|===========================|===========|============ ;;
            ;; ======================================|========|===============================================|=========|===========================|===========|============ ;;
            ;; ======================================|========|===============================================|=========|===========================|===========|============ ;;
            ("󱄅 microvisor  : arch:upgrade"         :command "sudo pacman -Syu                 "                                                  :annotation "    pacman ")
            ("󱄅 microvisor  : debian:upgrade"       :command "sudo apt update && sudo apt upgrade -y"                                             :annotation "       apt ")
            ("󱄅 microvisor  : openbsd:upgrade"      :command "doas pkg_add -u                  "                                                  :annotation "   pkg_add ")
            ("󱄅 microvisor  :󰣠 freebsd:upgrade"      :command "sudo pkg update && pkg upgrade -y"                                                  :annotation "       pkg 󰣠")
            ("󱄅 microvisor  : darwin:switch"        :command "darwin-rebuild switch --flake .  "                                                  :annotation "       nix ")
            ("󱄅 microvisor  :󰘳 darwin:rebuild"       :command "darwin-rebuild build  --flake .  "                                                  :annotation "       nix ")
            ("󱄅 microvisor  : guix:pull"            :command "guix pull                        "                                                  :annotation "      guix ")
            ("󱄅 microvisor  : nixos:rebuild"        :command "nixos-rebuild  build  --flake .  "                                                  :annotation "       nix ")
            ;; ======================================|========|================================================|=========|=================================================== ;;
            ;; ======================================|========|================================================|=========|=================================================== ;;
            (" pulumi  :󱓞 pulumi up"                :command "pulumi up -fyv=3"                                                                   :annotation "    pulumi ")
            (" pulumi  :󰢈 pulumi destroy"           :command "pulumi state unprotect --all -y; pulumi destroy -y; pulumi refresh -y;"             :annotation "    pulumi ")
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ("󰕮 microtop 󰕮 : run"                    :command "cargo r -rp microtop"                          :prodigy t                           :annotation "     cargo ")
            ("󰕮 microtop 󰕮 :󰳽 serve"                  :command "trunk serve --config apps/microtop/Trunk.toml" :prodigy t :port 8080                :annotation "     cargo ")
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            (" buttercup  :󰳽 test"                  :command "for pkg in ~/MFarabi619/modules/home/programs/emacs/extra/*/Eask; do (cd \"${pkg%/Eask}\" && eask test buttercup); done"                :annotation "     emacs  ")
            ;; ======================================|========|================================================|=========|=================================================== ;;
            ;; ======================================|========|================================================|=========|=================================================== ;;
            (" tui  : run"                         :command "cargo r -rp tui"                               :prodigy t                           :annotation "     cargo ")
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            ;; ======================================|========|================================================|=========|==========================|===========|============ ;;
            (" firmware  :󰍹 example:simulator"      :command "cargo r -rp firmware --example simulator"      :prodigy t                           :annotation "     cargo ")
            (" firmware  :󰇉 example:simulator(min)" :command "cargo r -rp firmware --example simulator-minimal"       :prodigy t                  :annotation "     cargo ")
            (" firmware  :󰳽 serve"                  :command "trunk serve"                                   :prodigy t :port 8080                :annotation "     cargo ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" ESP32S3  : build"                   :command "cargo +esp bb -r"                                                                   :annotation "cargo +esp ")
            (" ESP32S3  :󱈝 build:partition"         :command "cargo espflash partition-table firmware/boards/esp32s3.partitions.csv"              :annotation "cargo +esp ")
            (" ESP32S3  :󰔰 flash"                   :command "cargo +esp flash --target xtensa-esp32s3-none-elf"                                  :annotation "cargo +esp ")
            (" ESP32S3  : upload"                  :command "cargo loco t upload"                                                                :annotation "cargo +esp ")
            (" ESP32S3  : debug"                   :command "espflash partition-table firmware/machine/esp32s3.partitions.csv; cargo +esp rr"    :annotation "cargo +esp ")
            (" ESP32S3  :󰭎 monitor"                 :command "probe-rs run"                                  :prodigy nil                         :annotation "cargo +esp ")
            (" ESP32S3  :󱈫 test"                    :command "cargo +esp tt                     "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󱠡 test:hello"              :command "cargo +esp tt --test hello        "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰋊 test:spi"                :command "cargo +esp tt --test spi          "                                                 :annotation "cargo +esp ")
            (" ESP32S3  : test:sd"                 :command "cargo +esp tt --test sd           "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰹤 test:ota"                :command "cargo +esp tt --test ota          "                                                 :annotation "cargo +esp ")
            (" ESP32S3  : test:i2c"                :command "cargo +esp tt --test i2c          "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰒪 test:sntp"               :command "cargo +esp tt --test sntp         "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰜤 test:scd30"              :command "cargo +esp tt --test scd30        "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰟤 test:scd4x"              :command "cargo +esp tt --test scd4x        "                                                 :annotation "cargo +esp ")
            (" ESP32S3  : e2e:system"              :command "cargo +esp tt --test system       "                                                 :annotation "cargo +esp ")
            (" ESP32S3  : test:ds3231"             :command "cargo +esp tt --test ds3231       "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󱡬 example:gpio"            :command "cargo +esp rr --example gpio      "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󱂛 test:http_api"           :command "cargo +esp tt --test http_api     "                                                 :annotation "cargo +esp ")
            (" ESP32S3  : test:filesystem"         :command "cargo +esp tt --test filesystem   "                                                 :annotation "cargo +esp ")
            (" ESP32S3  : test:ntc_formula"        :command "cargo +esp tt --test ntc_formula  "                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰈘 test:sd_card_webpage"    :command "cargo +esp tt --test sd_card_webpage"                                               :annotation "cargo +esp ")
            ;; (" ESP32S3  : example:mdns"            :command "cargo +esp rr --example mdns_responder"                                             :annotation "cargo +esp ")
            (" ESP32S3  :󰒲 example:deep_sleep"      :command "cargo +esp rr --example deep_sleep"                                                 :annotation "cargo +esp ")
            (" ESP32S3  :󰒲 example:defmt-tcp"       :command "cargo +esp rr --example defmt-tcp "                                                 :annotation "cargo +esp ")
            ;; ======================================|========|=====================================================================================|===========|============ ;;
            ;; ======================================|========|=====================================================================================|===========|============ ;;
            (" ESP32  : run"                       :command "cargo +esp rr"                                                                      :annotation "cargo +esp ")
            ;; ======================================|========|============================================================================================================== ;;
            ;; ======================================|========|============================================================================================================== ;;
            ;; ======================================|========|============================================================================================================== ;;
            ("󰚗 STM32H723ZG 󰚗 :󰔰 flash"               :command "cargo r -r    --bin stm32h723zg                    --target thumbv7em-none-eabihf"  :annotation "     cargo ")
            ("󰚗 STM32H723ZG 󰚗 : debug"               :command "cargo r       --bin stm32h723zg                    --target thumbv7em-none-eabihf"  :annotation "     cargo ")
            ;; ======================================|========|============================================================================================================== ;;
            )))
       ;; ===========================================|========|============================================================================================================== ;;
       (eval . (let* ((extra-dir (expand-file-name "modules/home/programs/emacs/extra/" (locate-dominating-file default-directory ".dir-locals.el"))) (microvisor-dir (expand-file-name "microvisor/" extra-dir)))
                 (add-to-list 'load-path microvisor-dir)
                 (load (expand-file-name "microvisor" microvisor-dir) 'noerror 'nomessage)))

       ;; ============================================================================================================================================================ ;;
       ;; (add-to-list
       ;;  'dape-configs
       ;;  '(probe-rs
       ;;    :chip "esp32s3" :request "launch" :type "probe-rs-debug" :consoleLogLevel "Console" :flashingConfig (:flashingEnabled t)

       ;;    port :autoport host "localhost" command "probe-rs"
       ;;    modes (rust-mode rustic-mode)
       ;;    compile "cargo +esp b -p firmware  --example gpio --target xtensa-esp32s3-none-elf"
       ;;    command-args ("dap-server" "--port" ":autoport")
       ;;    command-cwd (lambda () (project-root (project-current)))
       ;;    :fn (lambda (config) (if (derived-mode-p 'dape-repl-mode) config (plist-put config 'compile nil)))
       ;;    :coreConfigs [(
       ;;                   :coreIndex 0
       ;;                   :rttEnabled t
       ;;                   :rttChannelFormats [(:channelNumber 0 :showTimestamps t :dataFormat "String")]
       ;;                   :svdFile (lambda () (let ((f (expand-file-name "firmware/boards/esp32s3.svd" (project-root (project-current)))))
       ;;                                         (unless (file-exists-p f) (error "Missing SVD file: %s" f)) f))
       ;;                   :programBinary (lambda () (expand-file-name "target/xtensa-esp32s3-none-elf/debug/examples/gpio" (project-root (project-current))))
       ;;                   )]
       ;;    ))
       ;; ============================================================================================================================================================ ;;
       (eval . (with-eval-after-load 'dape
                 (setf (alist-get 'zephyr-stm32 dape-configs)
                       '(command "gdb" :request "attach" :target ":3333"
                         command-args ("--interpreter=dap")
                         ensure (lambda (config)
                                  (dape-ensure-command config)
                                  (let* ((output (shell-command-to-string "gdb --version"))
                                         (version (when (string-match "GNU gdb \\(?:(.*) \\)?\\([0-9.]+\\)" output)
                                                    (string-to-number (match-string 1 output)))))
                                    (unless (and version (>= version 14.1))
                                      (user-error "Requires gdb version >= 14.1"))))
                         :program (lambda () (expand-file-name "build/zephyr/zephyr.elf" (project-root (project-current))))))))

       (eval . (when (and buffer-file-name (string-match-p "/extra/[^/]+/.*-tests?\\.el\\'" buffer-file-name)) (buttercup-minor-mode 1)))
       )))
