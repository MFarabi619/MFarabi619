((nil .
      ((compile-multi-annotate-cmds . t)
       (compile-multi-annotate-limit . 10)
       (compile-multi-annotate-string-cmds . nil)
       (compile-multi-group-cmds . group-and-replace)
       (eval . (progn
                 (require 'compile-multi)
                 (require 'nerd-icons nil t)
                 (require 'subr-x)

                 (defvar my/compile-multi-annotation-icon-files
                   '(("cargo" . "Cargo.toml")
                     ("nix" . "flake.nix")
                     ("devenv" . "flake.nix")))

                 (defun my/compile-multi-annotation-prefix (annotation_text)
                   (car (split-string (string-trim-left annotation_text) "[[:space:]]+" t)))

                 (defun my/compile-multi-strip-trailing-annotation-icon (annotation_text)
                   (replace-regexp-in-string "\\s-*\\(\\|\\|󱄅\\)\\s-*$" ""
                                             (string-trim-right annotation_text)))

                 (defun my/compile-multi-truncate-annotation (annotation_text)
                   (if (and compile-multi-annotate-limit
                            (> (length annotation_text) compile-multi-annotate-limit))
                       (concat
                        (string-trim-right
                         (substring annotation_text 0 compile-multi-annotate-limit))
                        "…")
                     annotation_text))

                 (defun my/compile-multi-render-right-annotation (annotation_text icon_text)
                   (let* ((annotation_rendered
                           (concat
                            (propertize annotation_text 'face 'completions-annotations)
                            " "
                            icon_text))
                          (annotation_width
                           (string-width (substring-no-properties annotation_rendered))))
                     (concat
                      " "
                      (propertize
                       " "
                       'display `(space :align-to (- right ,(+ 1 annotation_width))))
                      annotation_rendered)))

                 (defun my/compile-multi-local-annotation-with-colored-icons (original-function task)
                   "Render compile-multi annotations with colored cargo/nix icons."
                   (let ((annotation_text (plist-get (cdr task) :annotation)))
                     (if (not (stringp annotation_text))
                         (funcall original-function task)
                       (let* ((annotation_prefix (my/compile-multi-annotation-prefix annotation_text))
                              (icon_file_name
                               (and annotation_prefix
                                    (cdr (assoc annotation_prefix my/compile-multi-annotation-icon-files)))))
                         (if (not (and icon_file_name
                                       (fboundp 'nerd-icons-icon-for-file)))
                             (funcall original-function task)
                           (let* ((annotation_base
                                   (my/compile-multi-strip-trailing-annotation-icon annotation_text))
                                  (annotation_text_truncated
                                   (my/compile-multi-truncate-annotation annotation_base))
                                  (annotation_icon
                                   (nerd-icons-icon-for-file icon_file_name)))
                             (my/compile-multi-render-right-annotation
                              annotation_text_truncated
                              annotation_icon)))))))

                 (when (advice-member-p
                        #'my/compile-multi-local-annotation-with-colored-icons
                        #'compile-multi--annotation-function)
                   (advice-remove
                    'compile-multi--annotation-function
                    #'my/compile-multi-local-annotation-with-colored-icons))

                 (advice-add
                  'compile-multi--annotation-function
                  :around
                  #'my/compile-multi-local-annotation-with-colored-icons)

                 (let* ((cargo-command-prefix "cargo")
                        (cargo-esp-command-prefix "cargo +esp")
                        (firmware-package-name "firmware")
                        (esp-feature-flag "-F esp32s3")
                        (esp-build-std-flag "--config 'unstable.build-std=[\"core\",\"alloc\"]'")
                        (esp32-target-flag "--target xtensa-esp32-none-elf")
                        (esp32s3-target-flag "--target xtensa-esp32s3-none-elf")
                        (stm32-target-flag "--target thumbv7em-none-eabihf")
                        (cargo-run-command
                         (lambda (package-name &optional binary-name release-enabled extra-flags)
                           (string-join
                            (delq nil
                                  (list cargo-command-prefix
                                        "r"
                                        (if release-enabled "-rp" "-p")
                                        package-name
                                        (when binary-name (format "--bin %s" binary-name))
                                        extra-flags))
                            " ")))
                        (cargo-esp-firmware-command
                         (lambda (subcommand release-enabled target-flag include-features extra-flags)
                           (string-join
                            (delq nil
                                  (list cargo-esp-command-prefix
                                        subcommand
                                        (if release-enabled "-rp" "-p")
                                        firmware-package-name
                                        (when include-features esp-feature-flag)
                                        extra-flags
                                        esp-build-std-flag
                                        target-flag))
                            " ")))
                        (devenv-service-commands
                         '(("󱄅 microvisor : sqld" . "sqld")
                           ("󱄅 microvisor : caddy" . "caddy")
                           ("󱄅 microvisor :󰇮 mailpit" . "mailpit")
                           ("󱄅 microvisor : postgres" . "postgres")
                           ("󱄅 microvisor :󰖟 tailscale" . "tailscale")
                           ("󱄅 microvisor : prometheus" . "prometheus")))
                        (esp32s3-test-targets
                         '((" ESP32S3 :󰙨 test:i2c " . "i2c")
                           (" ESP32S3 :󰙨 test:ds3231 " . "ds3231")
                           (" ESP32S3 :󰙨 test:filesystem " . "filesystem")
                           (" ESP32S3 :󰙨 test:ntc_formula " . "ntc_formula"))))
                   (setq-local
                    compile-multi-dir-local-config
                    `((t
                       ("󱄅 microvisor :󰔡 activate" :command "nix run .#activate"    :annotation "   nix ")
                       ("󱄅 microvisor :󰍉 info"     :command "devenv info"           :annotation "devenv 󱄅")
                       ("󱄅 microvisor : tasks"    :command "devenv tasks list"     :annotation "devenv 󱄅")
                       ("󱄅 microvisor : down"     :command "devenv processes down" :annotation "devenv 󱄅")
                       ,@(mapcar (lambda (service_entry)
                                   `(,(car service_entry)
                                     :command ,(format "devenv up %s -d" (cdr service_entry))
                                     :annotation "devenv 󱄅"))
                                 devenv-service-commands)
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

                       ("󰕮 microtop 󰕮:󰐊 run"      :command ,(funcall cargo-run-command "microtop" nil t nil)                         :annotation "     cargo ")
                       ("󱄅 microvisor :󰙨 test"   :command "cargo loco test"                                                        :annotation "cargo +esp ")
                       ("󰦉 web 󰦉:󰐊 run"           :command ,(funcall cargo-run-command "web" nil t nil)                              :annotation "     cargo ")
                       (" tui :󰐊 run"           :command ,(funcall cargo-run-command "tui" nil t nil)                              :annotation "     cargo ")
                       (" tui :󰇉 simulate"      :command ,(funcall cargo-run-command "tui" "simulator" t nil)                      :annotation "     cargo ")
                       (" tui :󰍹 simulate(min)" :command ,(funcall cargo-run-command "tui" "simulator-minimal" t nil)              :annotation "     cargo ")

                       (" ESP32 :󰐊 run"         :command ,(funcall cargo-esp-firmware-command "r" t esp32-target-flag t nil)       :annotation "cargo +esp ")
                        (" ESP32S3 : debug"     :command ,(funcall cargo-esp-firmware-command "r" nil esp32s3-target-flag nil nil) :annotation "cargo +esp ")
                        (" ESP32S3 :󰔰 flash"     :command ,(format "cargo +esp build --release -rp firmware -F esp32s3 --config 'unstable.build-std=[\"core\",\"alloc\"]' --target xtensa-esp32s3-none-elf && espflash partition-table firmware/partitions.csv && espflash flash --partition-table firmware/partitions.csv --erase-parts otadata target/xtensa-esp32s3-none-elf/release/esp32s3") :annotation "cargo +esp ")
                        (" ESP32S3 : monitor"   :command "probe-rs run --chip esp32s3 --idf-partition-table firmware/partitions.csv --log-format '{[{L:bold:green:4}]%bold} {ff:bold:magenta}:{l:bold:cyan} :: {s:bold:white}' target/xtensa-esp32s3-none-elf/release/esp32s3" :annotation "cargo +esp ")
                        (" ESP32S3 : upload"    :command "cargo loco t upload"    :annotation "cargo +esp ")
                       ,@(mapcar (lambda (test_entry) `(,(car test_entry)
                                                        :command ,(funcall cargo-esp-firmware-command "t" nil esp32s3-target-flag t (format "--test %s" (cdr test_entry)))
                                                        :annotation "cargo +esp "))
                                 esp32s3-test-targets)
                        (" ESP32S3 :󱉟 example:deep_sleep 󰒲" :command ,(funcall cargo-esp-firmware-command "r" nil esp32s3-target-flag t "--example deep_sleep") :annotation "cargo +esp ")
                        (" ESP32S3 :󰙨 test:ota_probe"        :command ,(funcall cargo-esp-firmware-command "t" nil esp32s3-target-flag t "--test ota_probe")    :annotation "cargo +esp ")

                       ("󰚗 STM32H723ZG 󰚗:󰐊 run"               :command ,(funcall cargo-run-command firmware-package-name "stm32h723zg" t stm32-target-flag)       :annotation "     cargo ")
                       ("󰚗 STM32H723ZG 󰚗: debug"             :command ,(funcall cargo-run-command firmware-package-name "stm32h723zg" nil stm32-target-flag)     :annotation "     cargo "))))))))))
