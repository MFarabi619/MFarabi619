((nil .
      (
       (compile-multi-annotate-cmds . t)
       (compile-multi-annotate-limit . 10)
       (compile-multi-annotate-string-cmds . t)
       (compile-multi-annotate-string-cmds . nil)
       (compile-multi-group-cmds . group-and-replace)
       (compile-multi-dir-local-config
        . ((t
            ("󱄅 microvisor :󰔡 activate"           :command "nix run .#activate"                      :annotation "   nix ")
            ("󱄅 microvisor :󰍉 info"               :command "devenv info"                             :annotation "devenv 󱄅")
            ("󱄅 microvisor : tasks"              :command "devenv tasks list"                       :annotation "devenv 󱄅")
            ("󱄅 microvisor : down"               :command "devenv processes down"                   :annotation "devenv 󱄅")
            ("󱄅 microvisor : sqld"               :command "devenv up sqld -d"                       :annotation "devenv 󱄅")
            ("󱄅 microvisor : caddy"              :command "devenv up caddy -d"                      :annotation "devenv 󱄅")
            ("󱄅 microvisor :󰇮 mailpit"            :command "devenv up mailpit -d"                    :annotation "devenv 󱄅")
            ("󱄅 microvisor : postgres"           :command "devenv up postgres -d"                   :annotation "devenv 󱄅")
            ("󱄅 microvisor :󰖟 tailscale"          :command "devenv up tailscale -d"                  :annotation "devenv 󱄅")
            ("󱄅 microvisor : prometheus"         :command "devenv up prometheus -d"                 :annotation "devenv 󱄅")
            ;; ("󱄅 microvisor :󰏓 build"              :command "darwin-rebuild build --flake ."          :annotation "nix-darwin ")
            ;; (when (eq system-type 'freebsd)
            ;;   ("󱄅 microvisor : update:upgrade"   :command "pkg update && pkg upgrade -y"            :annotation "pkg    󰣠"))
            ;; (when (eq system-type 'openbsd)
            ;;   ("󱄅 microvisor : update:upgrade"   :command "pkg-update && pkg upgrade -y"            :annotation "pkg_add "))
            ;; (when (eq system-type 'darwin)
            ;;   ("󱄅 microvisor : rebuild:switch"   :command "darwin rebuild switch --flake ."         :annotation "nix    "))
            ;; (when (eq system-type 'debian)
            ;;   ("󱄅 microvisor : update:upgrade"   :command "pkg update && pkg upgrade -y"            :annotation "apt    "))
            ;; (when (eq system-type 'arch-linux)
            ;;   ("󱄅 microvisor : update:upgrade"   :command "pkg update && pkg upgrade -y"            :annotation "pacman "))

            ("󰕮 microtop 󰕮:󰐊 run"                  :command "cargo r -rp microtop"                    :annotation " cargo ")
            ("󰦉 web 󰦉:󰐊 run"                       :command "cargo r -rp microtop"                    :annotation " cargo ")
            (" tui :󰐊 run"                       :command "cargo r -rp tui"                         :annotation " cargo ")
            (" tui :󰇉 simulate"                  :command "cargo r -rp tui --bin simulator"         :annotation " cargo ")
            (" tui :󰍹 simulate(min)"             :command "cargo r -rp tui --bin simulator-minimal" :annotation " cargo ")

            (" ESP32 :󰐊 run"                     :command "cargo +esp r -rp firmware -F esp32s3                      --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32-none-elf"   :annotation "cargo +esp ")

            (" ESP32S3 :󰡢 build"                 :command "cargo +esp b -rp firmware -F esp32s3                      --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 : debug"                 :command "cargo +esp r -p  firmware                                 --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰔰 flash"                 :command "cargo +esp r -rp firmware -F esp32s3                      --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 : upload"                :command "cargo +esp b -rp firmware -F esp32s3                      --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 : partition"             :command "cargo +esp b -rp firmware -F esp32s3                      --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:i2c "           :command "cargo +esp t -p  firmware -F esp32s3 --test i2c           --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:ds3231 "        :command "cargo +esp t -p  firmware -F esp32s3 --test ds3231        --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:filesystem "    :command "cargo +esp t -p  firmware -F esp32s3 --test filesystem    --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:ntc_formula "   :command "cargo +esp t -p  firmware -F esp32s3 --test ntc_formula   --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󱉟 example:deep_sleep 󰒲" :command "cargo +esp r -p  firmware -F esp32s3 --example deep_sleep --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")

            ("󰚗 STM32H723ZG 󰚗:󰐊 run"               :command "cargo      r -rp firmware            --bin stm32h723zg                                                       --target thumbv7em-none-eabihf"   :annotation "cargo ")
            ("󰚗 STM32H723ZG 󰚗: debug"             :command "cargo      r -p  firmware            --bin stm32h723zg                                                       --target thumbv7em-none-eabihf"   :annotation "cargo ")
            ))))
      ))

;; ((nil . ((compile-multi-group-cmds . group-and-replace)
;;          (compile-multi-annotate-cmds . t)
;;          (compile-multi-annotate-string-cmds . t)
;;          (compile-multi-annotate-limit . 80)
;;          (eval . (progn
;;                    (require 'nerd-icons)
;;                    (setq-local
;;                     compile-multi-dir-local-config
;;                     `((t
;;                        (,(format "devenv:%s tasks list"
;;                                  (nerd-icons-mdicon "nf-md-format_list_bulleted"))
;;                         . "devenv tasks list")
;;                        (,(format "devenv:%s up postgres"
;;                                  (nerd-icons-mdicon "nf-md-database_arrow_up"))
;;                         . "devenv up postgres -d")
;;                        (,(format "devenv:%s info"
;;                                  (nerd-icons-mdicon "nf-md-information_outline"))
;;                         . "devenv info")

;;                        (,(format "firmware:%s test i2c"
;;                                  (nerd-icons-mdicon "nf-md-connection"))
;;                         . "cargo loco task test firmware:i2c")
;;                        (,(format "firmware:%s test ntc_formula"
;;                                  (nerd-icons-mdicon "nf-md-function"))
;;                         . "cargo loco task test firmware:ntc_formula")
;;                        (,(format "firmware:%s test filesystem"
;;                                  (nerd-icons-mdicon "nf-md-database"))
;;                         . "cargo loco task test firmware:filesystem")
;;                        (,(format "firmware:%s test deep_sleep"
;;                                  (nerd-icons-mdicon "nf-md-sleep"))
;;                         . "cargo loco task test firmware:deep_sleep")

;;                        (,(format "loco:%s task"
;;                                  (nerd-icons-mdicon "nf-md-hammer_wrench"))
;;                         . "cargo loco task")
;;                        (,(format "loco:%s routes"
;;                                  (nerd-icons-mdicon "nf-md-routes"))
;;                         . "cargo loco routes")
;;                        (,(format "loco:%s doctor"
;;                                  (nerd-icons-mdicon "nf-md-stethoscope"))
;;                         . "cargo loco doctor")

;;                        (,(format "nix:%s activate"
;;                                  (nerd-icons-mdicon "nf-md-snowflake"))
;;                         . "nix run .#activate")))))))))

;; ((nil . ((compile-multi-group-cmds . group-and-replace)
;;          (compile-multi-annotate-cmds . t)
;;          (compile-multi-annotate-string-cmds . t)
;;          (compile-multi-annotate-limit . 80)
;;          (compile-multi-nerd-icons-alist
;;           . ((devenv   nerd-icons-mdicon  "nf-md-package_variant" :face nerd-icons-blue)
;;              (firmware nerd-icons-mdicon  "nf-md-chip"            :face nerd-icons-lblue)
;;              (loco     nerd-icons-mdicon  "nf-md-tools"           :face nerd-icons-orange)
;;              (nix      nerd-icons-mdicon  "nf-md-snowflake"       :face nerd-icons-cyan)
;;              (t        nerd-icons-mdicon  "nf-md-console"         :face nerd-icons-dsilver)))
;;          (compile-multi-dir-local-config
;;           . ((t
;;               ("devenv:tasks list" . "devenv tasks list")
;;               ("devenv:up postgres" . "devenv up postgres -d")
;;               ("devenv:info" . "devenv info")

;;               ("firmware:test i2c" . "cargo loco task test firmware:i2c")
;;               ("firmware:test ntc_formula" . "cargo loco task test firmware:ntc_formula")
;;               ("firmware:test filesystem" . "cargo loco task test firmware:filesystem")
;;               ("firmware:test deep_sleep" . "cargo loco task test firmware:deep_sleep")

;;               ("loco:task" . "cargo loco task")
;;               ("loco:routes" . "cargo loco routes")
;;               ("loco:doctor" . "cargo loco doctor")

;;               ("nix:activate" . "nix run .#activate"))))))))
