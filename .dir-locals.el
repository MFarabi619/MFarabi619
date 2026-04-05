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
      ((compile-multi-annotate-cmds . t)
       (compile-multi-annotate-limit . 10)
       (compile-multi-annotate-string-cmds . nil)
       (compile-multi-group-cmds . group-and-replace)
       ;; ================================================================================================================================================================== ;;
       (compile-multi-dir-local-config
        . ((t
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󱄅 microvisor :󰔡 activate"           :command "nix run .#activate"                                                                 :annotation "       nix ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󱄅 microvisor :󰋽 info"               :command "devenv info"                                  :prodigy t                            :annotation "    devenv 󱄅")
            ("󱄅 microvisor :󰇺 tasks"              :command "devenv tasks list"                            :prodigy t                            :annotation "    devenv 󱄅")
            ("󱄅 microvisor :󰚦 down"               :command "devenv processes down"                        :prodigy t                            :annotation "    devenv 󱄅")
            ("󱄅 microvisor : sqld"               :command "devenv up sqld"                               :prodigy t :port 8080                 :annotation "    devenv 󱄅")
            ("󱄅 microvisor : caddy"              :command "devenv up caddy"                              :prodigy t :port   80                 :annotation "    devenv 󱄅")
            ("󱄅 microvisor :󰇮 mailpit"            :command "devenv up mailpit"                            :prodigy t :port 8025                 :annotation "    devenv 󱄅")
            ("󱄅 microvisor : postgres"           :command "devenv up postgres"                           :prodigy t :port 5432                 :annotation "    devenv 󱄅")
            ("󱄅 microvisor : tailscale"          :command "devenv up tailscale"                          :prodigy t :port 8080                 :annotation "    devenv 󱄅")
            ("󱄅 microvisor : prometheus"         :command "devenv up prometheus"                         :prodigy t :port 9090                 :annotation "    devenv 󱄅")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" loco : start"                    :command "cargo loco start"                             :prodigy t :port 5150                 :annotation "     cargo ")
            (" loco : db"                       :command "cargo loco db"                                :prodigy t                            :annotation "     cargo ")
            (" loco :󱤟 db:status"                :command "cargo loco db status"                         :prodigy t                            :annotation "     cargo ")
            (" loco :󱘽 db:migrate:up"            :command "cargo loco db migrate up"                     :prodigy t                            :annotation "     cargo ")
            (" loco :󱘼 db:migrate:down"          :command "cargo loco db migrate up"                     :prodigy t                            :annotation "     cargo ")
            (" loco :󰆺 db:seed"                  :command "cargo loco db seed"                           :prodigy t                            :annotation "     cargo ")
            (" loco :󰑪 routes"                   :command "cargo loco routes"                            :prodigy t                            :annotation "     cargo ")
            (" loco :󰣖 jobs"                     :command "cargo loco jobs"                              :prodigy t                            :annotation "     cargo ")
            (" loco : doctor"                   :command "cargo loco doctor"                            :prodigy t                            :annotation "     cargo ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󱄅 microvisor : openbsd:upgrade"    :command "doas pkg_add -u                  "                                                  :annotation "   pkg_add ")
            ("󱄅 microvisor :󰣠 freebsd:upgrade"    :command "sudo pkg update && pkg upgrade -y"                                                  :annotation "       pkg 󰣠")
            ("󱄅 microvisor : darwin:switch"      :command "darwin-rebuild switch --flake .  "                                                  :annotation "       nix ")
            ("󱄅 microvisor :󰘳 darwin:rebuild"     :command "darwin-rebuild build  --flake .  "                                                  :annotation "       nix ")
            ("󱄅 microvisor : guix:pull"          :command "guix pull                        "                                                  :annotation "      guix ")
            ("󱄅 microvisor : nixos:rebuild"      :command "nixos-rebuild  build  --flake .  "                                                  :annotation "       nix ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󱄅 microvisor : arch:upgrade"       :command "sudo pacman -Syu                 "                                                  :annotation "    pacman ")
            ("󱄅 microvisor : debian:upgrade"     :command "sudo apt update && sudo apt upgrade -y"                                             :annotation "       apt ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󰕮 microtop 󰕮:󰐊 run"                  :command "cargo r -rp microtop"                          :prodigy t                           :annotation "     cargo ")
            ("󰕮 microtop 󰕮:󰳽 serve"                :command "trunk serve --config apps/microtop/Trunk.toml" :prodigy t :port 8080                :annotation "     cargo ")
            ;; ======================================|=======|============================================================================================================== ;;
            ;; ======================================|=======|============================================================================================================== ;;
            ("󰦉 web 󰦉:󰳽 serve"                     :command "dx serve  -p web"                              :prodigy t                           :annotation "    dioxus ")
            ("󰦉 web 󰦉:󰟀 serve:desktop"             :command "dx serve  -p web"                              :prodigy t                           :annotation "    dioxus ")
            ("󰦉 web 󰦉: serve:ssg"                 :command "dx serve -rp web --ssg"                        :prodigy t :port 8080                :annotation "    dioxus ")
            ("󰦉 web 󰦉:󰡢 build"                     :command "dx build  -p web"                              :prodigy t                           :annotation "    dioxus ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" tui :󰐊 run"                       :command "cargo r -rp tui"                               :prodigy t                           :annotation "     cargo ")
            (" tui :󰐊 run:simulate 󰇉"           :command "cargo r -rp tui --bin simulator"               :prodigy t                           :annotation "     cargo ")
            (" tui :󰐊 run:simulate(min) 󰍹"      :command "cargo r -rp tui --bin simulator-minimal"       :prodigy t                           :annotation "     cargo ")
            (" tui :󰳽 serve"                     :command "trunk serve"                                   :prodigy t :port 8080                :annotation "     cargo ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" ESP32 :󰐊 run"                     :command "cargo +esp r -rp firmware -F esp32s3                     --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32-none-elf"   :annotation "cargo +esp ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" ESP32S3 : upload"                :command "cargo loco t upload"                                                                :annotation "cargo +esp ")
            (" ESP32S3 :󰐊 run"                   :command "probe-rs run --preset esp32s3 --idf-partition-table firmware/partitions.csv --log-format '{[{L:bold:green:4}]%bold} {ff:bold:magenta}:{l:bold:cyan} :: {s:bold:white}' target/xtensa-esp32s3-none-elf/release/esp32s3"           :annotation "cargo +esp ")
            (" ESP32S3 :󰔰 flash"                 :command "espflash partition-table firmware/partitions.csv && cargo +esp flash --chip esp32s3 --binary-format idf --idf-partition-table firmware/partitions.csv -- -rp firmware --bin esp32s3 --target xtensa-esp32s3-none-elf -F esp32s3 --config 'unstable.build-std=[\"core\",\"alloc\"]'"       :annotation "cargo +esp ")
            (" ESP32S3 : debug"                 :command "cargo +esp r -p  firmware                                 --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰭎 monitor"               :command "probe-rs run --preset esp32s3 --idf-partition-table firmware/partitions.csv --log-format '{[{L:bold:green:4}]%bold} {ff:bold:magenta}:{l:bold:cyan} :: {s:bold:white}' target/xtensa-esp32s3-none-elf/release/esp32s3"           :annotation "cargo +esp ")
            (" ESP32S3 :󱈝 partition"             :command "cargo espflash partition-table boards/esp32s3.partitions.csv"                                                                                  :annotation "cargo +esp ")
            (" ESP32S3 : test:I2C"              :command "cargo +esp t -p  firmware -F esp32s3 --test i2c           --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 : test:DS3231"           :command "cargo +esp t -p  firmware -F esp32s3 --test ds3231        --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰜤 test:SCD30"            :command "cargo +esp t -p  firmware -F esp32s3 --test scd30         --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰟤 test:SCD4x"            :command "cargo +esp t -p  firmware -F esp32s3 --test scd4x         --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󱤭 test:OTA"              :command "cargo +esp t -p  firmware -F esp32s3 --test ota_probe     --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 : test:filesystem"       :command "cargo +esp t -p  firmware -F esp32s3 --test filesystem    --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 : test:ntc_formula"      :command "cargo +esp t -p  firmware -F esp32s3 --test ntc_formula   --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰒲 example:deep_sleep"    :command "cargo +esp r -p  firmware -F esp32s3 --example deep_sleep --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            ;; ======================================|=======|============================================================================================================== ;;
            ;; ======================================|=======|============================================================================================================== ;;
            ;; ======================================|=======|============================================================================================================== ;;
            ("󰚗 STM32H723ZG 󰚗:󰐊 run"               :command "cargo      r -rp firmware            --bin stm32h723zg                                                       --target thumbv7em-none-eabihf"   :annotation "     cargo ")
            ("󰚗 STM32H723ZG 󰚗: debug"             :command "cargo      r -p  firmware            --bin stm32h723zg                                                       --target thumbv7em-none-eabihf"   :annotation "     cargo "))))
       ;; ===========================================|=======|============================================================================================================== ;;
       (eval . (progn
                 (require 'seq) (require 'cl-lib) (require 'subr-x) (require 'prodigy) (require 'compile-multi) (require 'nerd-icons nil t)
                 ;; ========================================================================================================================================================= ;;
                 (defun my/compile-multi-local-annotation (original-function task)
                   (if-let* ((annotation_text (plist-get (cdr task) :annotation)) ((stringp annotation_text)) ((fboundp 'nerd-icons-icon-for-file))
                             (annotation_words (split-string (string-trim-right annotation_text) "[[:space:]]+" t))
                             (icon_file_name (alist-get (car annotation_words) '(("cargo" . "Cargo.toml") ("nix" . "flake.nix") ("devenv" . "flake.nix")) nil nil #'string=)))
                       (let* ((annotation_base (string-join (if (> (length annotation_words) 1) (butlast annotation_words) annotation_words) " "))
                              (annotation_text_truncated (if (and compile-multi-annotate-limit (> (length annotation_base) compile-multi-annotate-limit))
                                                             (concat (truncate-string-to-width annotation_base compile-multi-annotate-limit) "…") annotation_base))
                              (annotation_rendered (concat (propertize annotation_text_truncated 'face 'completions-annotations) " " (nerd-icons-icon-for-file icon_file_name)))
                              (annotation_width (string-width (substring-no-properties annotation_rendered))))
                         (concat " " (propertize " " 'display `(space :align-to (- right ,(+ 1 annotation_width)))) annotation_rendered))
                     (funcall original-function task))) ;; end defun my/compile-multi-local-annotation
                 ;; ========================================================================================================================================================= ;;
                 (unless (advice-member-p #'my/compile-multi-local-annotation #'compile-multi--annotation-function)
                   (advice-add 'compile-multi--annotation-function :around #'my/compile-multi-local-annotation)) ;; end unless
                 (defun my/compile-multi-running-prodigy-face (original-function tasks)
                   (mapcar
                    (lambda (task)
                      (let* ((title (car task))
                             (plist (cdr task))
                             (plain-title (substring-no-properties title))
                             (service (and (plist-get plist :prodigy)
                                           (prodigy-find-service plain-title))))
                        (if (and service (prodigy-service-started-p service))
                            (let ((title* (copy-sequence title)))
                              (add-face-text-property 0 (length title*) 'prodigy-green-face t title*)
                              (cons title* plist))
                          task)))
                    (funcall original-function tasks)))

                 (unless (advice-member-p #'my/compile-multi-running-prodigy-face #'compile-multi--add-properties)
                   (advice-add 'compile-multi--add-properties :around #'my/compile-multi-running-prodigy-face))
                 ;; ========================================================================================================================================================= ;;
                 (dolist (task (seq-filter (lambda (task) (plist-get (cdr task) :prodigy)) (thread-first (compile-multi--config-tasks) (compile-multi--fill-tasks) (compile-multi--add-properties))))

                   (let* ((title        (car task))
                          (plist        (cdr task))
                          (port         (plist-get plist :port))
                          (plain-title  (substring-no-properties title))
                          (command      (or (get-text-property 0 'compile-multi--task title) (plist-get plist :command)))
                          (group-label  (or (get-text-property 0 'consult--type title) (if (string-match "\\`\\([^:]+\\):\\(.*\\)\\'" plain-title) (string-trim (match-string 1 plain-title)) plain-title)))
                          (display-name (if (string-match "\\`\\([^:]+\\):\\(.*\\)\\'" plain-title) (string-trim (match-string 2 plain-title)) plain-title)))

                     (apply #'prodigy-define-service
                            (append
                             (list
                              :stop-signal                 'kill
                              :name                        plain-title
                              :display-name                display-name
                              :group-label                 (format "%s" group-label)
                              :kill-process-buffer-on-stop 'unless-visible
                              :command                     shell-file-name
                              :cwd                         (projectile-project-root)
                              :args                        (list shell-command-switch command))
                             (when port                    (list :port port))))))
                 ;; ========================================================================================================================================================= ;;
                 )) ;; end eval
       )))
