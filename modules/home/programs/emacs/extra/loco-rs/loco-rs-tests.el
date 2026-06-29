;;; loco-rs-tests.el --- Buttercup tests for loco-rs.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'nerd-icons)
(require 'seq)
(require 'loco-rs)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(defmacro loco-rs-tests--with-project (files &rest body)
  "Run BODY in a throwaway loco project built from FILES.
FILES is an alist of (RELATIVE-PATH . CONTENT).  `dir' is bound to the project
root; LOCO_ENV/RAILS_ENV/NODE_ENV are unset for a deterministic environment."
  (declare (indent 1))
  `(let ((dir (make-temp-file "loco-rs-test" t))
          (process-environment (copy-sequence process-environment)))
     (setenv "LOCO_ENV" nil)
     (setenv "RAILS_ENV" nil)
     (setenv "NODE_ENV" nil)
     (unwind-protect
       (progn
         (dolist (file ,files)
           (let ((path (expand-file-name (car file) dir)))
             (make-directory (file-name-directory path) t)
             (with-temp-file path (insert (cdr file)))))
         ,@body)
       (delete-directory dir t))))

(defconst loco-rs-tests--expected
  ;; DISPLAY            COMMAND                       ICON-FN            ICON-NAME
  '(("start"     "cargo loco start"      nerd-icons-devicon "nf-dev-rails")
     ("db"        "cargo loco db"         nerd-icons-devicon "nf-dev-database")
     ("db:status" "cargo loco db status"  nerd-icons-mdicon  "nf-md-database_eye")
     ("db:migrate" "cargo loco db migrate" nerd-icons-mdicon "nf-md-database_arrow_right")
     ("db:down"   "cargo loco db down"    nerd-icons-mdicon  "nf-md-database_arrow_left")
     ("db:seed"   "cargo loco db seed"    nerd-icons-mdicon  "nf-md-database_plus")
     ("routes"    "cargo loco routes"     nerd-icons-mdicon  "nf-md-routes")
     ("jobs"      "cargo loco jobs"       nerd-icons-mdicon  "nf-md-cogs")
     ("doctor"    "cargo loco doctor"     nerd-icons-faicon  "nf-fa-heart_pulse"))
  "Expected loco tasks, with labels and commands matching loco 0.16.x.
The `.dir-locals.el' `db:migrate:up'/`db:migrate:down' entries ran
`db migrate up'/`db migrate down', which loco 0.16 rejects; the real
subcommands are `db migrate' (up) and `db down' (down), so the labels are
renamed to `db:migrate' and `db:down' to match.")

(defun loco-rs-tests--task (display)
  "Return the generated task whose title ends with DISPLAY."
  (seq-find (lambda (task) (string-suffix-p display (car task)))
    (loco-rs-compile-multi-tasks)))

(describe "loco-rs-compile-multi-tasks"
  (it "generates exactly the nine loco tasks"
    (expect (length (loco-rs-compile-multi-tasks)) :to-equal 9))

  (it "groups every task under a train-glyphed `loco' header"
    (let ((train (nerd-icons-wicon "nf-weather-train")))
      (expect (seq-every-p (lambda (task)
                             (and (string-search "loco" (car task))
                               (string-search train (car task))))
                (loco-rs-compile-multi-tasks))
              :to-be-truthy)))

  (describe "each task reproduces its `.dir-locals' command and icon"
    (dolist (spec loco-rs-tests--expected)
      (let ((display   (nth 0 spec))
             (command  (nth 1 spec))
             (icon-fn  (nth 2 spec))
             (icon-name (nth 3 spec)))
        (it (format "renders `%s'" display)
          (let ((task (loco-rs-tests--task display)))
            (expect task :not :to-be nil)
            (expect (plist-get (cdr task) :command) :to-equal command)
            (expect (car task) :to-match (regexp-quote (funcall icon-fn icon-name))))))))

  (it "marks only the `start' server as a prodigy service"
    (expect (plist-get (cdr (loco-rs-tests--task "start")) :prodigy) :to-be-truthy)
    (dolist (display '("db" "db:status" "db:migrate" "db:down"
                        "db:seed" "routes" "jobs" "doctor"))
      (expect (plist-get (cdr (loco-rs-tests--task display)) :prodigy) :to-be nil)))

  (it "stamps the `start' server with the port loco-rs derives"
    (spy-on 'loco-rs--server-port :and-return-value 9999)
    (expect (plist-get (cdr (loco-rs-tests--task "start")) :port) :to-equal 9999))

  (it "annotates every task with the cargo icon"
    (expect (seq-every-p (lambda (task)
                           (string-match-p "cargo"
                             (or (plist-get (cdr task) :annotation) "")))
              (loco-rs-compile-multi-tasks))
            :to-be-truthy)))

(describe "loco-rs-project-p"
  (it "detects a project whose .cargo/config.toml defines a loco alias"
    (let ((dir (make-temp-file "loco-rs-test" t)))
      (unwind-protect
        (progn
          (make-directory (expand-file-name ".cargo" dir))
          (with-temp-file (expand-file-name ".cargo/config.toml" dir)
            (insert "[alias]\nloco = [\"run\", \"-p\", \"server\", \"--\"]\n"))
          (expect (loco-rs-project-p dir) :to-be-truthy))
        (delete-directory dir t))))

  (it "returns nil with a .cargo/config.toml that has no loco alias"
    (let ((dir (make-temp-file "loco-rs-test" t)))
      (unwind-protect
        (progn
          (make-directory (expand-file-name ".cargo" dir))
          (with-temp-file (expand-file-name ".cargo/config.toml" dir)
            (insert "[build]\ntarget = \"x86_64-unknown-linux-gnu\"\n"))
          (expect (loco-rs-project-p dir) :to-be nil))
        (delete-directory dir t))))

  (it "returns nil outside any cargo project"
    (let ((dir (make-temp-file "loco-rs-test" t)))
      (unwind-protect
        (expect (loco-rs-project-p dir) :to-be nil)
        (delete-directory dir t)))))

(describe "loco-rs--server-port"
  (it "reads server.port from the folder the .cargo alias points to"
    (loco-rs-tests--with-project
        '((".cargo/config.toml" . "[env]\nLOCO_CONFIG_FOLDER = { value = \"apps/server/config\", relative = true }\n")
           ("apps/server/config/development.yaml" . "server:\n    port: 1234\n    host: http://localhost\n"))
      (expect (loco-rs--server-port dir) :to-equal 1234)))

  (it "prefers <env>.local.yaml over <env>.yaml"
    (loco-rs-tests--with-project
        '((".cargo/config.toml" . "[env]\nLOCO_CONFIG_FOLDER = { value = \"config\", relative = true }\n")
           ("config/development.yaml" . "server:\n    port: 1111\n")
           ("config/development.local.yaml" . "server:\n    port: 2222\n"))
      (expect (loco-rs--server-port dir) :to-equal 2222)))

  (it "expands a get_env() port to its default when the var is unset"
    (loco-rs-tests--with-project
        '((".cargo/config.toml" . "[env]\nLOCO_CONFIG_FOLDER = { value = \"config\", relative = true }\n")
           ("config/development.yaml" . "server:\n    port: {{ get_env(name=\"NOPE_PORT\", default=4444) }}\n"))
      (expect (loco-rs--server-port dir) :to-equal 4444)))

  (it "falls back to `loco-rs-default-port' when no config is found"
    (loco-rs-tests--with-project
        '((".cargo/config.toml" . "[alias]\nloco = [\"run\", \"-p\", \"server\", \"--\"]\n"))
      (let ((loco-rs-default-port 5150))
        (expect (loco-rs--server-port dir) :to-equal 5150)))))

(describe "compile-multi integration"
  (it "registers the loco task generator in `compile-multi-config'"
    (expect (assoc '(loco-rs-project-p) compile-multi-config) :not :to-be nil)))

(provide 'loco-rs-tests)

;;; loco-rs-tests.el ends here
