((nil . ((compile-multi-group-cmds . group-and-replace)
         (compile-multi-annotate-cmds . t)
         (compile-multi-annotate-string-cmds . t)
         (compile-multi-annotate-limit . 80)
         (eval . (let* ((esp-target "xtensa-esp32s3-none-elf")
                        (esp-features "esp32s3")
                        (firmware-package "firmware")
                        (build-std-config "unstable.build-std=[\"core\",\"alloc\"]")
                        (cargo-esp-firmware-base
                         (format "cargo +esp --package %s --config '%s' --target %s --features %s"
                                 firmware-package build-std-config esp-target esp-features))
                        (firmware-test-command
                         (lambda (test-target-name)
                           (format "%s test --test %s"
                                   cargo-esp-firmware-base
                                   test-target-name)))
                        (firmware-example-command
                         (lambda (example-target-name)
                           (format "%s run --example %s"
                                   cargo-esp-firmware-base
                                   example-target-name))))
                   (setq-local
                    compile-multi-dir-local-config
                    `((t
                       ("󱄅 devenv:󰐕 tasks list" . "devenv tasks list")
                       ("󱄅 devenv:󰑐 up postgres" . "devenv up postgres --no-tui --detach")
                       ("󱄅 devenv:󰋽 info" . "devenv info")

                       ("󰚩 firmware:󰙨 test i2c" . ,(funcall firmware-test-command "i2c"))
                       ("󰚩 firmware:󱤅 test ntc_formula" . ,(funcall firmware-test-command "ntc_formula"))
                       ("󰚩 firmware:󰆼 test filesystem" . ,(funcall firmware-test-command "filesystem"))

                       ("󰚩 firmware:󰒲 run deep_sleep" . ,(funcall firmware-example-command "deep_sleep"))
                       ("󰚩 firmware:󰑮 build release" . ,(format "%s build --release --bin esp32s3" cargo-esp-firmware-base))

                       ("󱄅 nix:󰒓 activate" . "nix run .#activate")))))))))

;; ((nil . ((compile-multi-group-cmds . group-and-replace)
;;          (compile-multi-annotate-cmds . t)
;;          (compile-multi-annotate-string-cmds . t)
;;          (compile-multi-annotate-limit . 80)
;;          (compile-multi-dir-local-config
;;           . ((t
;;               ("󱄅 devenv:󰐕 tasks list" . "devenv tasks list")
;;               ("󱄅 devenv:󰑐 up postgres" . "devenv up postgres --no-tui --detach")
;;               ("󱄅 devenv:󰋽 info" . "devenv info")

;;               ("󰚩 firmware:󰙨 test i2c" . "cargo loco task test firmware:i2c")
;;               ("󰚩 firmware:󱤅 test ntc_formula" . "cargo loco task test firmware:ntc_formula")
;;               ("󰚩 firmware:󰆼 test filesystem" . "cargo loco task test firmware:filesystem")
;;               ("󰚩 firmware:󰒲 test deep_sleep" . "cargo loco task test firmware:deep_sleep")

;;               ("󱘖 loco:󰆍 task" . "cargo loco task")
;;               ("󱘖 loco:󰌗 routes" . "cargo loco routes")
;;               ("󱘖 loco:󰑓 doctor" . "cargo loco doctor")

;;               ("󱄅 nix:󰒓 activate" . "nix run .#activate"))))))))

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
;;                         . "devenv up postgres --no-tui --detach")
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
;;               ("devenv:up postgres" . "devenv up postgres --no-tui --detach")
;;               ("devenv:info" . "devenv info")

;;               ("firmware:test i2c" . "cargo loco task test firmware:i2c")
;;               ("firmware:test ntc_formula" . "cargo loco task test firmware:ntc_formula")
;;               ("firmware:test filesystem" . "cargo loco task test firmware:filesystem")
;;               ("firmware:test deep_sleep" . "cargo loco task test firmware:deep_sleep")

;;               ("loco:task" . "cargo loco task")
;;               ("loco:routes" . "cargo loco routes")
;;               ("loco:doctor" . "cargo loco doctor")

;;               ("nix:activate" . "nix run .#activate"))))))))
