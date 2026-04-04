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
            ("󱄅 microvisor :󰍉 info"               :command "devenv info"                                                                        :annotation "    devenv 󱄅")
            ("󱄅 microvisor : tasks"              :command "devenv tasks list"                                                                  :annotation "    devenv 󱄅")
            ("󱄅 microvisor : down"               :command "devenv processes down"                                                              :annotation "    devenv 󱄅")
            ("󱄅 microvisor : sqld"               :command "devenv up sqld -d"                                                                  :annotation "    devenv 󱄅")
            ("󱄅 microvisor : caddy"              :command "devenv up caddy -d"                                                                 :annotation "    devenv 󱄅")
            ("󱄅 microvisor :󰇮 mailpit"            :command "devenv up mailpit -d"                                                               :annotation "    devenv 󱄅")
            ("󱄅 microvisor : postgres"           :command "devenv up postgres -d"                                                              :annotation "    devenv 󱄅")
            ("󱄅 microvisor : tailscale"          :command "devenv up tailscale -d"                                                             :annotation "    devenv 󱄅")
            ("󱄅 microvisor : prometheus"         :command "devenv up prometheus -d"                                                            :annotation "    devenv 󱄅")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" loco : start"                    :command "cargo loco start"                                                                   :annotation "     cargo ")
            (" loco :󰑪 routes"                   :command "cargo loco routes"                                                                  :annotation "     cargo ")
            (" loco :󰣖 jobs"                     :command "cargo loco jobs"                                                                    :annotation "     cargo ")
            (" loco : doctor"                   :command "cargo loco doctor"                                                                  :annotation "     cargo ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󱄅 microvisor : openbsd:upgrade"    :command "doas pkg_add -u                  "                                                  :annotation "   pkg_add ")
            ("󱄅 microvisor : freebsd:upgrade"    :command "sudo pkg update && pkg upgrade -y"                                                  :annotation "       pkg 󰣠")
            ("󱄅 microvisor : darwin:switch"      :command "darwin-rebuild switch --flake .  "                                                  :annotation "       nix ")
            ("󱄅 microvisor :󰡢 darwin:rebuild"     :command "darwin-rebuild build  --flake .  "                                                  :annotation "       nix ")
            ("󱄅 microvisor : guix:update"        :command "guix pull                        "                                                  :annotation "      guix ")
            ("󱄅 microvisor :󰡢 nixos:rebuild"      :command "nixos-rebuild  build  --flake .  "                                                  :annotation "       nix ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󱄅 microvisor : arch:upgrade"       :command "sudo pacman -Syu                 "                                                  :annotation "    pacman ")
            ("󱄅 microvisor : debian:upgrade"     :command "sudo apt update && apt upgrade -y"                                                  :annotation "       apt ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ("󰕮 microtop 󰕮:󰐊 run"                  :command "cargo r -rp microtop"                                                               :annotation "     cargo ")
            ;; ======================================|=======|============================================================================================================== ;;
            ;; ======================================|=======|============================================================================================================== ;;
            ("󰦉 web 󰦉:󰐊 run"                       :command "dx serve  -p web"                                                                   :annotation "     cargo ")
            ("󰦉 web 󰦉:󰐊 run:ssg"                   :command "dx serve -rp web --ssg"                                                             :annotation "     cargo ")
            ("󰦉 web 󰦉:󰡢 build"                     :command "dx build  -p web"                                                                   :annotation "     cargo ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" tui :󰐊 run"                       :command "cargo r -rp tui"                                                                    :annotation "     cargo ")
            (" tui :󰇉 simulate"                  :command "cargo r -rp tui --bin simulator"                                                    :annotation "     cargo ")
            (" tui :󰍹 simulate(min)"             :command "cargo r -rp tui --bin simulator-minimal"                                            :annotation "     cargo ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" ESP32 :󰐊 run"                     :command "cargo +esp r -rp firmware -F esp32s3                     --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32-none-elf"   :annotation "cargo +esp ")
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            ;; ======================================|=======|=====================================================================================|===========|============ ;;
            (" ESP32S3 : upload"                :command "cargo loco t upload"                                                                :annotation "cargo +esp ")
            (" ESP32S3 :󰔰 flash"                 :command "cargo flash -rp  firmware -F esp32s3 --preset esp32s3     --config 'unstable.build-std=[\"core\",\"alloc\"]' --binary-format idf --idf-partition-table firmware/partitions.csv --target xtensa-esp32s3-none-elf"       :annotation "cargo +esp ")
            (" ESP32S3 :󰭎 monitor"               :command "probe-rs run --preset esp32s3 --idf-partition-table firmware/partitions.csv --log-format '{[{L:bold:green:4}]%bold} {ff:bold:magenta}:{l:bold:cyan} :: {s:bold:white}' target/xtensa-esp32s3-none-elf/release/esp32s3" :annotation "cargo +esp ")
            (" ESP32S3 : debug"                 :command "cargo +esp r -p  firmware                                 --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:i2c "           :command "cargo +esp t -p  firmware -F esp32s3 --test i2c           --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:ds3231 "        :command "cargo +esp t -p  firmware -F esp32s3 --test ds3231        --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:ota_probe 󱤭"     :command "cargo +esp t -p  firmware -F esp32s3 --test ota_probe     --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:filesystem "    :command "cargo +esp t -p  firmware -F esp32s3 --test filesystem    --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󰙨 test:ntc_formula "   :command "cargo +esp t -p  firmware -F esp32s3 --test ntc_formula   --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            (" ESP32S3 :󱉟 example:deep_sleep 󰒲" :command "cargo +esp r -p  firmware -F esp32s3 --example deep_sleep --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf" :annotation "cargo +esp ")
            ;; ======================================|=======|============================================================================================================== ;;
            ;; ======================================|=======|============================================================================================================== ;;
            ;; ======================================|=======|============================================================================================================== ;;
            ("󰚗 STM32H723ZG 󰚗:󰐊 run"               :command "cargo      r -rp firmware            --bin stm32h723zg                                                       --target thumbv7em-none-eabihf"   :annotation "     cargo ")
            ("󰚗 STM32H723ZG 󰚗: debug"             :command "cargo      r -p  firmware            --bin stm32h723zg                                                       --target thumbv7em-none-eabihf"   :annotation "     cargo "))))
       ;; ===========================================|=======|============================================================================================================== ;;
       (eval . (progn
                 (require 'seq)
                 (require 'cl-lib)
                 (require 'subr-x)
                 (require 'prodigy)
                 (require 'compile-multi)
                 (require 'nerd-icons nil t)
                 ;; ========================================================================================================================================================= ;;
                 (defun my/compile-multi-local-annotation (original-function task)
                   (if-let* ((annotation_text (plist-get (cdr task) :annotation))
                             ((stringp annotation_text))
                             ((fboundp 'nerd-icons-icon-for-file))
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
                 ;; ========================================================================================================================================================= ;;
                 (dolist (task (seq-filter
                                (lambda (task)
                                  (when-let ((command (plist-get (cdr task) :command)))
                                    (string-prefix-p "devenv up " command)))
                                (cdr (assq t compile-multi-dir-local-config))))
                   (prodigy-define-service
                     :name                        (string-trim (cadr (split-string (car task) ":")))
                     :command                     shell-file-name
                     :args                        (list shell-command-switch (plist-get (cdr task) :command))
                     :cwd                         default-directory
                     :stop-signal                 'kill
                     :kill-process-buffer-on-stop t
                     :tags                        (list (intern (string-trim (car (split-string (car task) ":")))))))

                 ;; ========================================================================================================================================================= ;;
                 )) ;; end eval
       )))
