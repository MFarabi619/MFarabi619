;;; pio-mode-tests.el --- Buttercup tests for pio-mode.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'pio-mode)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(buttercup-define-matcher-for-binary-function
  :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(buttercup-define-matcher :to-have-ports (entries expected-ports)
  "Match `pio--device-list-entries' output by its port list (id of each row)."
  (let ((entries (funcall entries))
         (expected (funcall expected-ports)))
    (let ((actual (mapcar #'car entries)))
      (if (equal actual expected)
        (cons t  (format "Expected entries NOT to have ports %S" expected))
        (cons nil (format "Expected entries to have ports %S, got %S" expected actual))))))

(buttercup-define-matcher :to-have-sections (config expected-sections)
  "Match a `pio-project-config' alist by its top-level section names, in order."
  (let ((cfg (funcall config))
         (expected (funcall expected-sections)))
    (let ((actual (mapcar #'car cfg)))
      (if (equal actual expected)
        (cons t  (format "Expected config NOT to have sections %S" expected))
        (cons nil (format "Expected config to have sections %S, got %S" expected actual))))))

(buttercup-define-matcher :to-render-substrings (rendered substrings)
  "Match a rendered string when every entry in SUBSTRINGS appears in it."
  (let ((text (funcall rendered))
         (subs (funcall substrings)))
    (let ((missing (seq-remove (lambda (s) (string-match-p (regexp-quote s) text)) subs)))
      (if (null missing)
        (cons t  (format "Expected rendered string NOT to contain all of %S" subs))
        (cons nil (format "Expected rendered string to contain %S, missing %S" subs missing))))))

(defmacro pio-tests--with-temp-dir (var &rest body)
  "Buttercup-friendly temp-dir: bind VAR to a fresh dir, run BODY, then delete it."
  (declare (indent 1))
  `(let ((,var (file-name-as-directory (make-temp-file "pio-test-" t))))
     (unwind-protect (progn ,@body)
       (delete-directory ,var t))))

(describe "pio-p"
  (it "is non-nil when platformio.ini is present"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (expect (pio-p dir))))

  (it "is nil when platformio.ini is absent"
    (pio-tests--with-temp-dir dir
      (expect (pio-p dir) :not :to-be-truthy))))

(describe "pio-root"
  (it "walks up from a subdirectory to find the project root"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (let ((subdir (expand-file-name "src" dir)))
        (make-directory subdir)
        (let ((default-directory subdir))
          (expect (pio-root) :to-be-file-equal dir)))))

  (it "returns nil when no project is found in the parent chain"
    (pio-tests--with-temp-dir dir
      (let ((default-directory dir))
        (expect (pio-root) :not :to-be-truthy)))))

(describe "pio-in-project-p"
  (it "is non-nil inside a PlatformIO project"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (let ((default-directory dir))
        (expect (pio-in-project-p))))))

(describe "pio-name"
  (it "returns the directory name of the project root"
    (pio-tests--with-temp-dir dir
      (let ((proj-dir (expand-file-name "my-project" dir)))
        (make-directory proj-dir)
        (write-region "" nil (expand-file-name "platformio.ini" proj-dir))
        (expect (pio-name proj-dir) :to-equal "my-project")))))

(describe "pio-config-file"
  (it "returns <project-root>/platformio.ini"
    (expect (pio-config-file "/some/proj/")
      :to-equal "/some/proj/platformio.ini")))

(defun pio-tests--make-project (dir config)
  "Create a platformio.ini at DIR and stub `pio--read-project-config' to CONFIG."
  (write-region "" nil (expand-file-name "platformio.ini" dir))
  (pio-project-config-invalidate)
  (spy-on 'pio--read-project-config :and-return-value config))

(describe "pio-project-config"
  (before-each (pio-project-config-invalidate))

  (it "returns nil when platformio.ini is absent"
    (pio-tests--with-temp-dir dir
      (expect (pio-project-config dir) :not :to-be-truthy)))

  (it "delegates to pio--read-project-config and returns its result"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir '(("platformio" ("name" . "demo"))))
      (expect (pio-project-config dir)
        :to-equal '(("platformio" ("name" . "demo"))))))

  (it "caches the parsed config and skips reading on subsequent calls"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir '(("platformio" ("name" . "demo"))))
      (pio-project-config dir)
      (pio-project-config dir)
      (pio-project-config dir)
      (expect 'pio--read-project-config :to-have-been-called-times 1)))

  (it "re-reads when the platformio.ini mtime changes"
    (pio-tests--with-temp-dir dir
      (let ((ini (expand-file-name "platformio.ini" dir)))
        (pio-tests--make-project dir '(("platformio" ("name" . "v1"))))
        (pio-project-config dir)
        (set-file-times ini (time-add (current-time) 5))
        (pio-project-config dir)
        (expect 'pio--read-project-config :to-have-been-called-times 2))))

  (it "invalidates a single project on demand"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir '(("platformio" ("name" . "demo"))))
      (pio-project-config dir)
      (pio-project-config-invalidate dir)
      (pio-project-config dir)
      (expect 'pio--read-project-config :to-have-been-called-times 2)))

  (describe "against a real `pio project config' capture (microvisor workspace)"
    (before-each
      (spy-on 'pio--run-json-as
        :and-return-value
        (json-parse-string (pio-tests--fixture "pio-project-config.json")
          :object-type 'hash-table :array-type 'list
          :false-object nil :null-object nil))
      (pio-project-config-invalidate))

    (it "preserves section ordering, including non-env templates"
      (pio-tests--with-temp-dir dir
        (write-region "" nil (expand-file-name "platformio.ini" dir))
        (expect (pio-project-config dir) :to-have-sections
          '("platformio" "native" "env:clay"
             "embedded" "env:ceratina" "env:walter-iot" "env:esp32p4"))))

    (it "surfaces only `env:' sections through `pio-envs'"
      (pio-tests--with-temp-dir dir
        (write-region "" nil (expand-file-name "platformio.ini" dir))
        (expect (pio-envs dir) :to-equal '("clay" "ceratina" "walter-iot" "esp32p4"))))

    (it "normalizes a single-element `default_envs' into a list"
      (pio-tests--with-temp-dir dir
        (write-region "" nil (expand-file-name "platformio.ini" dir))
        (expect (pio-default-envs dir) :to-equal '("ceratina"))))

    (it "resolves per-env board names through `pio-env-board'"
      (pio-tests--with-temp-dir dir
        (write-region "" nil (expand-file-name "platformio.ini" dir))
        (expect (pio-env-board "ceratina" dir) :to-equal "esp32-s3-devkitc1-n8r8")
        (expect (pio-env-board "esp32p4"  dir) :to-equal "esp32-p4")))))

(describe "pio-project-metadata"
  (before-each
    (pio-project-metadata-invalidate)
    (spy-on 'pio--run-json-as
      :and-return-value
      (json-parse-string (pio-tests--fixture "pio-project-metadata.json")
        :object-type 'hash-table :array-type 'list
        :false-object nil :null-object nil)))

  (it "returns parsed per-env metadata"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (let ((meta (pio-project-metadata dir)))
        (expect (hash-table-p meta))
        (expect (gethash "ceratina" meta) :not :to-be nil))))

  (it "caches by `platformio.ini' mtime"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (pio-project-metadata dir)
      (pio-project-metadata dir)
      (pio-project-metadata dir)
      (expect 'pio--run-json-as :to-have-been-called-times 1)))

  (it "re-reads after `pio-project-metadata-invalidate'"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (pio-project-metadata dir)
      (pio-project-metadata-invalidate dir)
      (pio-project-metadata dir)
      (expect 'pio--run-json-as :to-have-been-called-times 2))))

(describe "pio-env-targets"
  (before-each
    (pio-project-metadata-invalidate)
    (spy-on 'pio--run-json-as
      :and-return-value
      (json-parse-string (pio-tests--fixture "pio-project-metadata.json")
        :object-type 'hash-table :array-type 'list
        :false-object nil :null-object nil)))

  (it "returns the list of buildable targets for a known env"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (let ((targets (pio-env-targets "ceratina" dir)))
        (expect (length targets) :to-be-greater-than 0)
        (expect (member "upload" targets) :not :to-be nil))))

  (it "returns nil for an unknown env"
    (pio-tests--with-temp-dir dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (expect (pio-env-targets "nonexistent" dir) :to-be nil))))

(describe "pio-envs"
  (before-each (pio-project-config-invalidate))

  (it "extracts env: section names in declaration order"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio"      ("default_envs" "release"))
           ("env:release"     ("build_type"   . "release"))
           ("env:debug"       ("build_type"   . "debug"))
           ("env:custom_plank" ("board"       . "custom"))))
      (expect (pio-envs dir)
        :to-equal '("release" "debug" "custom_plank"))))

  (it "ignores non-env sections like [platformio] and [embedded]"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio" ("default_envs" "release"))
           ("embedded"   ("framework" . "arduino"))
           ("env:dev"    ("board" . "esp32dev"))))
      (expect (pio-envs dir) :to-equal '("dev"))))

  (it "returns nil when no env: sections exist"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio" ("name" . "demo"))))
      (expect (pio-envs dir) :not :to-be-truthy)))

  (it "returns nil when platformio.ini is absent"
    (pio-tests--with-temp-dir dir
      (expect (pio-envs dir) :not :to-be-truthy))))

(describe "pio-default-envs"
  (before-each
    (pio-project-config-invalidate)
    (setenv "PLATFORMIO_DEFAULT_ENVS" nil))

  (it "returns the default_envs list from [platformio]"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio" ("default_envs" "release" "debug"))))
      (expect (pio-default-envs dir) :to-equal '("release" "debug"))))

  (it "handles a single-element default_envs list"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio" ("default_envs" "release"))))
      (expect (pio-default-envs dir) :to-equal '("release"))))

  (it "returns nil when default_envs is absent"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio" ("name" . "demo"))))
      (expect (pio-default-envs dir) :not :to-be-truthy)))

  (it "honors PLATFORMIO_DEFAULT_ENVS env var over the config value"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("platformio" ("default_envs" "from-config"))))
      (with-environment-variables (("PLATFORMIO_DEFAULT_ENVS" "from-env, also-env"))
        (expect (pio-default-envs dir)
          :to-equal '("from-env" "also-env"))))))

(describe "pio-build-dir"
  (before-each
    (setenv "PLATFORMIO_BUILD_DIR" nil))

  (it "returns <project-root>/.pio by convention"
    (expect (pio-build-dir "/some/proj/")
      :to-equal "/some/proj/.pio"))

  (it "honors PLATFORMIO_BUILD_DIR env var when set"
    (with-environment-variables (("PLATFORMIO_BUILD_DIR" "/custom/build"))
      (expect (pio-build-dir "/some/proj/") :to-equal "/custom/build"))))

(defconst pio-tests--fixtures-dir
  (expand-file-name "fixtures/"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the `pio-<command>.json' fixtures captured from real CLI output.")

(defun pio-tests--fixture (name)
  "Return the contents of `fixtures/NAME' as a string.
Safe to call from inside spec bodies; the directory is resolved at load time."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name pio-tests--fixtures-dir))
    (buffer-string)))

(defconst pio-tests--fixture-manifest
  '(("pio-account-show.json"        "account" "show"             "--json-output")
     ("pio-system-info.json"         "system"  "info"             "--json-output")
     ("pio-device-list-serial.json"  "device"  "list" "--serial"  "--json-output")
     ("pio-device-list-logical.json" "device"  "list" "--logical" "--json-output")
     ("pio-boards.json"              "boards"  "esp32-s3"         "--json-output")
     ("pio-org-list.json"            "org"     "list"             "--json-output")
     ("pio-team-list.json"           "team"    "list" "acme-corp" "--json-output")
     ("pio-project-config.json"      "project" "config"            "--json-output")
     ("pio-project-metadata.json"    "project" "metadata"          "--json-output"))
  "Alist mapping `fixtures/FILE.json' → the `pio' subcommand args that produced it.
Used by the auto-generated parse + freshness specs in the
\"fixtures (auto-generated)\" suite.  Drop a new fixture in the
manifest and you get free parse-cleanly + live-drift coverage.")

(defcustom pio-tests-project-root nil
  "Project root for the `pio project config' freshness spec.
Set in your local config (e.g. `direnv', `.dir-locals.el') to enable
the project-config drift check; left nil otherwise so CI doesn't fail."
  :type '(choice (const :tag "Skip" nil) directory)
  :group 'pio)

(defcustom pio-tests-real-org nil
  "Real organization name for the `pio team list' freshness spec.
The fixture stores a scrubbed `acme-corp' placeholder, so the live
CLI must be re-invoked with the real org name to compare."
  :type '(choice (const :tag "Skip" nil) string)
  :group 'pio)

(defun pio-tests--run-pio (args)
  "Run `pio ARGS' and return stdout as a string. Signals on non-zero exit."
  (with-temp-buffer
    (let ((exit (apply #'call-process "pio" nil t nil args)))
      (unless (zerop exit)
        (error "pio %s failed (exit %d): %s"
          (string-join args " ") exit (buffer-string)))
      (buffer-string))))

(describe "every captured fixture"
  (dolist (entry pio-tests--fixture-manifest)
    (let* ((name    (car entry))
            (args    (cdr entry))
            (cli-str (format "pio %s" (string-join args " "))))

      (it (format "%s parses as non-empty JSON" name)
        (let ((content (pio-tests--fixture name)))
          (expect (length content) :to-be-greater-than 0)
          (expect (json-parse-string content) :not :to-throw)))

      (it (format "stays in sync with `%s' on the running machine" cli-str)
        (assume (executable-find "pio") "pio not on PATH")
        (when (equal (car args) "project")
          (assume pio-tests-project-root
            "`pio-tests-project-root' unset"))
        (when (equal (car args) "team")
          (assume pio-tests-real-org
            "`pio-tests-real-org' unset (scrubbed org name in fixture)"))
        (let* ((full-args (cond
                            ((equal (car args) "project")
                              (append (butlast args 1)  ; drop --json-output
                                (list "-d" pio-tests-project-root "--json-output")))
                            ((equal (car args) "team")
                              (append (list "team" "list" pio-tests-real-org "--json-output")))
                            (t args)))
                (raw (pio-tests--run-pio full-args)))
          (expect (length raw) :to-be-greater-than 0)
          (expect (json-parse-string raw) :not :to-throw))))))

(defconst pio-tests--system-info-json (pio-tests--fixture "pio-system-info.json"))

(describe "pio-system-info accessors"
  (before-each
    (setq pio--system-info-cache nil)
    (spy-on 'pio--run-json
      :and-return-value (json-parse-string pio-tests--system-info-json)))

  (it "parses `pio system info' JSON into title+value plists"
    (expect (pio-core-version)
      :to-equal '(:title "PlatformIO Core" :value "6.1.19"))
    (expect (pio-core-dir)
      :to-equal '(:title "PlatformIO Core Directory"
                   :value "/Users/x/.platformio"))
    (expect (pio-platformio-exe)
      :to-equal '(:title "PlatformIO Core Executable"
                   :value "/Users/x/.local/bin/platformio")))

  (it "caches `pio system info' across calls"
    (pio-core-version)
    (pio-python-version)
    (pio-platformio-exe)
    (expect 'pio--run-json :to-have-been-called-times 1))

  (it "re-fetches after `pio-system-info-invalidate'"
    (pio-core-version)
    (pio-system-info-invalidate)
    (pio-core-version)
    (expect 'pio--run-json :to-have-been-called-times 2))

  (it "returns nil for fields not present in the JSON"
    (expect (pio--system-info-field "no_such_key") :not :to-be-truthy)))

(describe "pio--detect-executables"
  (it "finds pio and platformio across `exec-path' entries"
    (pio-tests--with-temp-dir dir1
      (pio-tests--with-temp-dir dir2
        (let ((pio1 (expand-file-name "pio" dir1))
               (pio2 (expand-file-name "platformio" dir2)))
          (write-region "" nil pio1)
          (write-region "" nil pio2)
          (set-file-modes pio1 #o755)
          (set-file-modes pio2 #o755)
          (let ((exec-path (list dir1 dir2)))
            (expect (pio--detect-executables)
              :to-have-same-items-as (list pio1 pio2)))))))

  (it "returns a single entry when only one binary is on `exec-path'"
    (pio-tests--with-temp-dir dir
      (let ((pio (expand-file-name "pio" dir)))
        (write-region "" nil pio)
        (set-file-modes pio #o755)
        (let ((exec-path (list dir)))
          (expect (pio--detect-executables) :to-equal (list pio)))))))

(describe "pio--warn-multiple-executables"
  (before-each
    (setq pio--multiple-executables-warned nil)
    (when-let ((buf (get-buffer "*Warnings*")))
      (let ((inhibit-read-only t))
        (with-current-buffer buf (erase-buffer)))))

  (it "writes a `pio'-categorized warning to *Warnings* when more than one binary is on PATH"
    (spy-on 'pio--detect-executables
      :and-return-value '("/a/pio" "/b/platformio"))
    (buttercup-suppress-warning-capture
      (pio--warn-multiple-executables)
      (expect (with-current-buffer "*Warnings*" (buffer-string))
        :to-match "Multiple PlatformIO executables")))

  (it "stays silent when only one binary is on PATH"
    (spy-on 'pio--detect-executables :and-return-value '("/a/pio"))
    (spy-on 'display-warning)
    (pio--warn-multiple-executables)
    (expect 'display-warning :not :to-have-been-called))

  (it "warns at most once per session"
    (spy-on 'pio--detect-executables
      :and-return-value '("/a/pio" "/b/platformio"))
    (spy-on 'display-warning)
    (pio--warn-multiple-executables)
    (pio--warn-multiple-executables)
    (pio--warn-multiple-executables)
    (expect 'display-warning :to-have-been-called-times 1)))

(describe "pio--read-key"
  (before-each (pio-project-config-invalidate))

  (it "reads a key from a named section"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("env:dev" ("board"    . "esp32dev")
            ("platform" . "espressif32"))))
      (expect (pio--read-key "env:dev" "board"    dir) :to-equal "esp32dev")
      (expect (pio--read-key "env:dev" "platform" dir) :to-equal "espressif32")))

  (it "does not read keys outside the named section"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("env:a" ("board"     . "esp32dev"))
           ("env:b" ("framework" . "arduino"))))
      (expect (pio--read-key "env:a" "framework" dir) :not :to-be-truthy)
      (expect (pio--read-key "env:b" "board"     dir) :not :to-be-truthy)))

  (it "returns nil when the section is absent"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir '(("env:dev" ("board" . "esp32dev"))))
      (expect (pio--read-key "env:missing" "board" dir) :not :to-be-truthy)))

  (it "returns nil when the section exists but the key does not"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir '(("env:dev" ("board" . "esp32dev"))))
      (expect (pio--read-key "env:dev" "framework" dir) :not :to-be-truthy)))

  (it "returns native typed values (numbers, lists, booleans)"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("env:dev" ("monitor_speed"  . 115200)
            ("monitor_filters" "direct" "colorize")
            ("test_build_src" . t))))
      (expect (pio--read-key "env:dev" "monitor_speed"   dir) :to-equal 115200)
      (expect (pio--read-key "env:dev" "monitor_filters" dir)
        :to-equal '("direct" "colorize"))
      (expect (pio--read-key "env:dev" "test_build_src"  dir) :to-equal t))))

(describe "pio-env-board"
  (before-each (pio-project-config-invalidate))
  (it "reads the board key from the [env:ENV] section"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("env:walter" ("board"    . "esp32dev")
            ("platform" . "espressif32"))))
      (expect (pio-env-board "walter" dir) :to-equal "esp32dev"))))

(describe "pio-env-platform"
  (before-each (pio-project-config-invalidate))
  (it "reads the platform key from the [env:ENV] section"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("env:walter" ("board"    . "esp32dev")
            ("platform" . "espressif32"))))
      (expect (pio-env-platform "walter" dir) :to-equal "espressif32"))))

(describe "pio-env-framework"
  (before-each (pio-project-config-invalidate))
  (it "reads the framework key from the [env:ENV] section"
    (pio-tests--with-temp-dir dir
      (pio-tests--make-project dir
        '(("env:walter" ("board"     . "esp32dev")
            ("framework" "arduino"))))
      (expect (pio-env-framework "walter" dir) :to-equal '("arduino")))))

(describe "vterm kill-buffer contract"
  (it "killing a vterm buffer kills the underlying subprocess"
    (assume (and (not noninteractive) (fboundp 'vterm) (executable-find "sleep"))
      "vterm lifecycle requires an interactive frame")
    (let ((vterm-shell "sleep 60")
           (vterm-buffer-name "*pio-test-vterm-lifecycle*")
           (kill-buffer-query-functions nil))
      (when (get-buffer vterm-buffer-name) (kill-buffer vterm-buffer-name))
      (vterm)
      (let* ((buffer (get-buffer vterm-buffer-name))
              (proc   (get-buffer-process buffer)))
        (expect (process-live-p proc))
        (kill-buffer buffer)
        (sleep-for 0.3)
        (expect (process-live-p proc) :not :to-be-truthy)))))

(describe "M-x visibility (only `pio' should surface; rest are dashboard-driven)"
  (it "hides the internal/dashboard-driven commands from M-x"
    (dolist (sym '(pio-device-monitor pio-device-monitor-mode pio--device-monitor-send-C-c))
      (expect (get sym 'completion-predicate) :to-equal #'ignore))))

(describe "pio-device-monitor interactive auto-port-pick"
  (before-each
    (spy-on 'pio-device-monitor :and-call-fake (lambda (&rest _) nil))
    (spy-on 'pio))

  (it "with exactly one connected serial port, auto-uses it (no prompt)"
    (spy-on 'pio--connected-serial-ports
      :and-return-value '("/dev/cu.usbmodem1101"))
    (expect (let ((current-prefix-arg nil))
              (call-interactively #'pio-device-monitor))
      :not :to-throw)
    (expect 'pio-device-monitor
      :to-have-been-called-with :port "/dev/cu.usbmodem1101")
    (expect 'pio :not :to-have-been-called))

  (it "with zero or multiple ports, drops the user into the *pio* dashboard"
    (spy-on 'pio--connected-serial-ports
      :and-return-value '("/dev/cu.A" "/dev/cu.B"))
    (expect (let ((current-prefix-arg nil))
              (call-interactively #'pio-device-monitor))
      :to-throw 'user-error)
    (expect 'pio :to-have-been-called))

  (it "with prefix arg, still prompts for a profile (existing behavior)"
    (spy-on 'completing-read :and-return-value "esp")
    (let ((pio-device-monitor-profiles '((esp :port "/dev/cu.X" :baud 115200))))
      (let ((current-prefix-arg '(4)))
        (call-interactively #'pio-device-monitor)))
    (expect 'pio-device-monitor :to-have-been-called-with :profile 'esp)))

(describe "pio-device-monitor"
  (it "vterm backend passes the resolved command to vterm via `vterm-shell'"
    (let ((pio-device-monitor-backend 'vterm)
           (pio-executable "pio")
           (pio-device-monitor-profiles
             '((esp :port "/dev/cu.usbmodem1101" :baud 115200
                 :filters ("direct"))))
           captured-shell captured-name)
      (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                 ((symbol-function 'pio-default-envs) (lambda (&rest _) nil))
                 ((symbol-function 'vterm)
                   (lambda (&rest _)
                     (setq captured-shell vterm-shell
                       captured-name  vterm-buffer-name))))
        (pio-device-monitor :profile 'esp))
      (expect captured-shell :to-equal
        "pio device monitor --port /dev/cu.usbmodem1101 --baud 115200 --filter direct")
      (expect captured-name :to-equal "*pio:monitor:/dev/cu.usbmodem1101*")))

  (it "serial-term backend calls `serial-term' with port + baud (no prompts) and does NOT rename the buffer"
    (require 'term)
    (let* ((pio-device-monitor-backend 'serial-term)
            (pio-executable "pio")
            (pio-device-monitor-profiles
              '((esp :port "/dev/cu.usbmodem1101" :baud 115200
                  :filters ("direct"))))
            captured-port captured-baud)
      (cl-letf (((symbol-function 'pio-default-envs) (lambda (&rest _) nil))
                 ((symbol-function 'serial-term)
                   (lambda (port baud &optional _line-mode)
                     (setq captured-port port captured-baud baud)
                     (generate-new-buffer "*tmp-serial-term*"))))
        (pio-device-monitor :profile 'esp))
      (expect captured-port :to-equal "/dev/cu.usbmodem1101")
      (expect captured-baud :to-equal 115200)
      (expect (get-buffer "*pio:monitor:/dev/cu.usbmodem1101*") :to-be nil)
      (let (kill-buffer-query-functions)
        (kill-buffer "*tmp-serial-term*"))))

  (it "serial-term backend reuses an existing live serial process for the same port"
    (require 'term)
    (let* ((pio-device-monitor-backend 'serial-term)
            (pio-device-monitor-profiles
              '((esp :port "/dev/cu.usbmodem1101" :baud 115200)))
            (existing-buf (generate-new-buffer "*pretend-serial*")))
      (spy-on 'pop-to-buffer)
      (spy-on 'serial-term)
      (cl-letf (((symbol-function 'pio-default-envs) (lambda (&rest _) nil))
                 ((symbol-function 'pio--device-monitor-serial-term-find)
                   (lambda (_port) existing-buf)))
        (pio-device-monitor :profile 'esp))
      (expect 'pop-to-buffer :to-have-been-called-with existing-buf)
      (expect 'serial-term :not :to-have-been-called)
      (let (kill-buffer-query-functions) (kill-buffer existing-buf))))

  (it "vterm backend reuses an existing `*pio:monitor:PORT*' buffer if its process is live"
    (let* ((pio-device-monitor-backend 'vterm)
            (bufname "*pio:monitor:/dev/cu.usbmodem1101*")
            (existing (generate-new-buffer bufname)))
      (spy-on 'pop-to-buffer)
      (spy-on 'vterm)
      (spy-on 'get-buffer-process :and-return-value 'pretend-proc)
      (spy-on 'process-live-p :and-return-value t)
      (unwind-protect
        (let ((pio-device-monitor-profiles
                '((esp :port "/dev/cu.usbmodem1101" :baud 115200
                    :filters ("direct"))))
               (pio-executable "pio"))
          (cl-letf (((symbol-function 'pio-default-envs) (lambda (&rest _) nil)))
            (pio-device-monitor :profile 'esp))
          (expect 'pop-to-buffer :to-have-been-called)
          (expect 'vterm :not :to-have-been-called))
        (let (kill-buffer-query-functions) (kill-buffer existing))))))

(defun pio-tests--make-device (port description hwid)
  (let ((dev (make-hash-table :test 'equal)))
    (puthash "port" port dev)
    (puthash "description" description dev)
    (puthash "hwid" hwid dev)
    dev))

(describe "pio--parse-hwid"
  (it "extracts vid-pid, serial, and location from a full hwid string"
    (expect (pio--parse-hwid
              "USB VID:PID=303A:1001 SER=CC:BA:97:16:2B:68 LOCATION=1-1")
      :to-equal
      '(:vid-pid "303A:1001"
         :serial  "CC:BA:97:16:2B:68"
         :location "1-1")))

  (it "returns only the keys that appear in the input"
    (expect (pio--parse-hwid "USB VID:PID=10C4:EA60")
      :to-equal '(:vid-pid "10C4:EA60")))

  (it "returns nil for a non-string or absent hwid"
    (expect (pio--parse-hwid nil) :to-equal nil)
    (expect (pio--parse-hwid "n/a") :to-equal nil)))

(defun pio-tests--row-strings (row)
  "Strip face properties from each cell in a tabulated-list ROW vector."
  (mapcar #'substring-no-properties (append (cadr row) nil)))

(describe "pio--device-list-entries"
  (it "puts SERIAL and VID:PID first, then PORT, LOCATION, and DESCRIPTION last"
    (spy-on 'pio-serial-devices :and-return-value
      (vector
        (pio-tests--make-device
          "/dev/cu.usbmodem1101" "USB JTAG/serial debug unit"
          "USB VID:PID=303A:1001 SER=CC:BA:97:16:2B:68 LOCATION=1-1")))
    (let ((entries (pio--device-list-entries)))
      (expect (length entries) :to-equal 1)
      (expect (car (car entries)) :to-equal "/dev/cu.usbmodem1101")
      (expect (pio-tests--row-strings (car entries))
        :to-equal
        '("CC:BA:97:16:2B:68"
           "303A:1001"
           "/dev/cu.usbmodem1101"
           "1-1"
           "USB JTAG/serial debug unit"))))

  (it "leaves hwid columns empty when the hwid string is missing"
    (spy-on 'pio-serial-devices :and-return-value
      (vector (pio-tests--make-device "/dev/cu.x" nil "VID:PID=0000:0000")))
    (expect (pio-tests--row-strings (car (pio--device-list-entries)))
      :to-equal '("" "0000:0000" "/dev/cu.x" "" "")))

  (it "hides devices whose hwid is \"n/a\" when `hide-unidentified' is t"
    (spy-on 'pio-serial-devices :and-return-value
      (vector
        (pio-tests--make-device "/dev/cu.Bluetooth-Incoming-Port" "n/a" "n/a")
        (pio-tests--make-device "/dev/cu.PowerbeatsPro"           "n/a" "n/a")
        (pio-tests--make-device "/dev/cu.debug-console"           "n/a" "n/a")
        (pio-tests--make-device "/dev/cu.usbmodem1101" "USB JTAG" "VID:PID=303A:1001")))
    (let* ((pio-device-list-hide-unidentified t)
            (pio-device-list-exclude-regexps nil)
            (entries (pio--device-list-entries)))
      (expect (length entries) :to-equal 1)
      (expect (car (car entries)) :to-equal "/dev/cu.usbmodem1101")))

  (it "filters by `exclude-regexps' on top of the heuristic"
    (spy-on 'pio-serial-devices :and-return-value
      (vector
        (pio-tests--make-device "/dev/cu.usbserial-FTDI"  "FTDI" "VID:PID=0403:6001")
        (pio-tests--make-device "/dev/cu.usbmodem1101"    "USB JTAG" "VID:PID=303A:1001")))
    (let* ((pio-device-list-hide-unidentified t)
            (pio-device-list-exclude-regexps '("FTDI"))
            (entries (pio--device-list-entries)))
      (expect (length entries) :to-equal 1)
      (expect (car (car entries)) :to-equal "/dev/cu.usbmodem1101")))

  (it "shows every device when both filters are disabled"
    (spy-on 'pio-serial-devices :and-return-value
      (vector
        (pio-tests--make-device "/dev/cu.Bluetooth-Incoming-Port" "n/a" "n/a")
        (pio-tests--make-device "/dev/cu.usbmodem1101" "x" "y")))
    (let ((pio-device-list-hide-unidentified nil)
           (pio-device-list-exclude-regexps nil))
      (expect (length (pio--device-list-entries)) :to-equal 2)))

  (describe "against a real `pio device list --serial' capture (macOS, 4 ports)"
    :var (entries)
    (before-each
      (spy-on 'pio--run-json-as
        :and-return-value
        (json-parse-string (pio-tests--fixture "pio-device-list-serial.json")
          :object-type 'hash-table :array-type 'array
          :false-object nil :null-object nil))
      (let ((pio-device-list-hide-unidentified t)
             (pio-device-list-exclude-regexps nil))
        (setq entries (pio--device-list-entries))))

    (it "filters every `n/a' system/Bluetooth/headphone entry, keeping only the real USB device"
      (expect entries :to-have-ports '("/dev/cu.usbmodem101")))

    (it "extracts SERIAL, VID:PID, and LOCATION from the hwid string into the row cells"
      (let ((row (cadr (car entries))))
        (expect (aref row 0) :to-equal "CC:BA:97:16:2B:68")
        (expect (aref row 1) :to-equal "303A:1001")
        (expect (aref row 2) :to-equal "/dev/cu.usbmodem101")
        (expect (aref row 3) :to-equal "0-1")
        (expect (aref row 4) :to-equal "USB JTAG/serial debug unit")))))

;;; Account

(defconst pio-tests--account-json (pio-tests--fixture "pio-account-show.json"))

(defun pio-tests--account ()
  "Return the sample account fixture parsed into the shape `pio-account-show' yields."
  (json-parse-string pio-tests--account-json
    :object-type 'hash-table
    :array-type  'list
    :false-object nil
    :null-object  nil))

(describe "pio--run-json"
  (it "signals `pio-exec-error' on non-zero exit"
    (cl-letf (((symbol-function 'process-file)
                (lambda (&rest _) (insert "boom\n") 1)))
      (expect (pio--run-json "wat") :to-throw 'pio-exec-error)))

  (it "signals `pio-parse-error' when stdout is not JSON"
    (let (debug-on-error)
      (cl-letf (((symbol-function 'process-file)
                  (lambda (&rest _) (insert "not json {[") 0)))
        (expect (pio--run-json "account" "show" "--json-output")
          :to-throw 'pio-parse-error))))

  (it "subclasses can be caught as the generic `pio-error'"
    (cl-letf (((symbol-function 'process-file)
                (lambda (&rest _) (insert "boom") 1)))
      (expect (pio--run-json "wat") :to-throw 'pio-error))))

(describe "the typed-error contract propagates through every CLI-read path"
  (it "pio--read-project-config surfaces `pio-exec-error' from the underlying call"
    (spy-on 'pio--run-json-as :and-throw-error 'pio-exec-error)
    (expect (pio--read-project-config "/tmp/x") :to-throw 'pio-exec-error))

  (it "pio--read-project-config surfaces `pio-parse-error' from the underlying call"
    (spy-on 'pio--run-json-as :and-throw-error 'pio-parse-error)
    (expect (pio--read-project-config "/tmp/x") :to-throw 'pio-parse-error))

  (it "pio--device-list surfaces any `pio-error' subclass to its caller"
    (spy-on 'pio--run-json-as :and-throw-error 'pio-exec-error)
    (expect (pio--device-list "serial") :to-throw 'pio-error))

  (it "pio-system-info surfaces any `pio-error' subclass to its caller"
    (setq pio--system-info-cache nil)
    (spy-on 'pio--run-json :and-throw-error 'pio-parse-error)
    (expect (pio-system-info) :to-throw 'pio-error))

  (it "pio-account-show surfaces any `pio-error' subclass to its caller"
    (pio-account-invalidate)
    (spy-on 'pio--run-json :and-throw-error 'pio-exec-error)
    (expect (pio-account-show) :to-throw 'pio-error))

  (it "lets callers `condition-case' on the parent class to catch any read failure"
    (pio-account-invalidate)
    (spy-on 'pio--run-json :and-throw-error 'pio-parse-error)
    (let ((caught (condition-case err
                    (progn (pio-account-show) nil)
                    (pio-error (car err)))))
      (expect caught :to-equal 'pio-parse-error))))

(describe "pio-account-show"
  (before-each
    (pio-account-invalidate)
    (spy-on 'pio--run-json
      :and-call-fake (lambda (&rest _) (pio-tests--account))))

  (it "delegates to `pio--run-json' with the right args"
    (pio-account-show)
    (expect 'pio--run-json
      :to-have-been-called-with "account" "show" "--json-output"))

  (it "caches the parsed account across calls"
    (pio-account-show)
    (pio-account-show)
    (pio-account-show)
    (expect 'pio--run-json :to-have-been-called-times 1))

  (it "re-fetches when REFRESH is non-nil"
    (pio-account-show)
    (pio-account-show t)
    (expect 'pio--run-json :to-have-been-called-times 2))

  (it "re-fetches after `pio-account-invalidate'"
    (pio-account-show)
    (pio-account-invalidate)
    (pio-account-show)
    (expect 'pio--run-json :to-have-been-called-times 2)))

(describe "pio-account-* accessors"
  :var (account)
  (before-each (setq account (pio-tests--account)))

  (it "extracts the username"
    (expect (pio-account-username account) :to-equal "alice"))

  (it "extracts the email"
    (expect (pio-account-email account) :to-equal "alice@example.com"))

  (it "joins firstname + lastname into a fullname"
    (expect (pio-account-fullname account) :to-equal "Alice Example"))

  (it "extracts the stable user id"
    (expect (pio-account-user-id account)
      :to-equal "00000000-0000-0000-0000-000000000000"))

  (it "extracts the packages list"
    (expect (length (pio-account-packages account)) :to-equal 2))

  (it "extracts the subscriptions list (empty for free tier)"
    (expect (pio-account-subscriptions account) :to-equal nil))

  (it "extracts the account expiry epoch as an integer"
    (expect (pio-account-expire-at account) :to-be-greater-than 0)))

(describe "pio--render"
  :var (rendered)
  (before-each
    (spy-on 'pio-core-version
      :and-return-value '(:title "PlatformIO Core" :value "6.1.19"))
    (spy-on 'pio-serial-devices :and-return-value
      (vector (pio-tests--make-device
                "/dev/cu.usbmodem1101" "USB JTAG/serial debug unit"
                "USB VID:PID=303A:1001 SER=CC:BA:97:16:2B:68 LOCATION=1-1")))
    (spy-on 'pio-envs)
    (spy-on 'pio-default-envs)
    (spy-on 'pio-env-targets)
    (with-temp-buffer
      (pio--render)
      (setq rendered (buffer-string))))

  (it "renders a DEVICES section as the top heading"
    (expect rendered :to-match "\\`DEVICES"))

  (it "renders a header row with the column labels under the heading"
    (dolist (header '("SERIAL" "VID:PID" "PORT" "LOCATION" "DESCRIPTION"))
      (expect rendered :to-match (regexp-quote header))))

  (it "includes the connected device's port in the DEVICES section"
    (expect rendered :to-match "/dev/cu\\.usbmodem1101")))

(describe "pio--render — deferred work"
  (it "TODO: re-wire `pio--render-profile' into the dashboard")
  (it "TODO: schema-validation matcher comparing fixture vs live capture")
  (it "TODO: free-tier vs paid `subscriptions' rendering"))

(describe "pio--render-profile (still callable; just not wired into the dashboard yet)"
  :var (rendered)
  (before-each
    (with-temp-buffer
      (pio--render-profile (pio-tests--account))
      (setq rendered (buffer-string))))

  (it "renders the PROFILE heading with the username, full name, email, and user id"
    (expect rendered :to-render-substrings
      '("PROFILE" "alice" "Alice Example"
         "alice@example.com" "00000000-")))

  (it "renders the PACKAGES heading with each package title and description"
    (expect rendered :to-render-substrings
      '("PACKAGES (2)"
         "Remote Development for Developer"
         "Trusted Registry for Developer"
         "Forever Free Remote Development"
         "Forever Free Trusted Registry")))

  (it "renders SUBSCRIPTIONS as `none' when the subscriptions list is empty"
    (expect rendered :to-match "SUBSCRIPTIONS (none)")))

(describe "pio--set-mode-line"
  (before-each
    (spy-on 'pio-core-version
      :and-return-value '(:title "PlatformIO Core" :value "6.1.19")))

  (it "leaves `mode-name' alone so ibuffer's Mode column stays as `pio-mode'"
    (with-temp-buffer
      (pio-mode)
      (pio--set-mode-line (pio-tests--account))
      (expect mode-name :to-equal "pio-mode")))

  (it "puts core version + username on `mode-line-process' (the canonical per-buffer slot)"
    (with-temp-buffer
      (pio--set-mode-line (pio-tests--account))
      (let ((joined (apply #'concat mode-line-process)))
        (expect joined :to-match "v6\\.1\\.19")
        (expect joined :to-match "alice")))))

(describe "pio (interactive entry point)"
  (before-each
    (pio-account-invalidate)
    (spy-on 'pio--run-json
      :and-call-fake (lambda (&rest _) (pio-tests--account)))
    (spy-on 'pio-core-version
      :and-return-value '(:title "PlatformIO Core" :value "6.1.19"))
    (spy-on 'pio-envs)
    (spy-on 'pio-default-envs)
    (spy-on 'pio-env-targets)
    (spy-on 'pop-to-buffer))

  (after-each
    (when (get-buffer pio-buffer-name)
      (let (kill-buffer-query-functions)
        (kill-buffer pio-buffer-name))))

  (it "creates a `*pio*' buffer in `pio-mode'"
    (spy-on 'pio-serial-devices :and-return-value [])
    (pio)
    (let ((buffer (get-buffer pio-buffer-name)))
      (expect (buffer-live-p buffer))
      (with-current-buffer buffer
        (expect major-mode :to-equal 'pio-mode)
        (expect (buffer-string) :to-match "DEVICES"))))

  (it "is revertable via `revert-buffer'"
    (pio)
    (with-current-buffer pio-buffer-name
      (let ((before (buffer-string)))
        (revert-buffer nil t)
        (expect (buffer-string) :to-equal before)))))

(describe "pio-device-monitor-mode (serial-monitor C-c passthrough)"
  (it "pressing C-c sends a literal Ctrl-c to the underlying RTOS process"
    (spy-on 'vterm-send-key)
    (with-temp-buffer
      (pio-device-monitor-mode 1)
      (call-interactively (key-binding (kbd "C-c")))
      (expect 'vterm-send-key :to-have-been-called-with "c" nil nil t))))


(describe "pio--render-device device-row text property"
  (it "tags each data row with the port as `pio-device-port'"
    (spy-on 'pio-serial-devices :and-return-value
      (vector (pio-tests--make-device
                "/dev/cu.usbmodem101" "USB JTAG"
                "USB VID:PID=303A:1001 SER=AA LOCATION=1-1")))
    (with-temp-buffer
      (pio--render-devices)
      (goto-char (point-min))
      (re-search-forward "/dev/cu\\.usbmodem101")
      (expect (get-text-property (point) 'pio-device-port)
        :to-equal "/dev/cu.usbmodem101")))

  (it "does NOT tag the header row with a port"
    (spy-on 'pio-serial-devices :and-return-value [])
    (with-temp-buffer
      (pio--render-devices)
      (goto-char (point-min))
      (re-search-forward "SERIAL")
      (expect (get-text-property (point) 'pio-device-port) :to-be nil))))

(describe "pressing RET on a device row in the *pio* dashboard"
  (it "opens the monitor for that row's port"
    (spy-on 'pio-device-monitor)
    (with-temp-buffer
      (pio-mode)
      (let ((inhibit-read-only t))
        (insert (propertize "row\n" 'pio-device-port "/dev/cu.x")))
      (goto-char (point-min))
      (call-interactively (key-binding (kbd "RET")))
      (expect 'pio-device-monitor
        :to-have-been-called-with :port "/dev/cu.x")))

  (it "is a no-op on a non-device row (no port property)"
    (spy-on 'pio-device-monitor)
    (with-temp-buffer
      (pio-mode)
      (let ((inhibit-read-only t)) (insert "header line\n"))
      (goto-char (point-min))
      (call-interactively (key-binding (kbd "RET")))
      (expect 'pio-device-monitor :not :to-have-been-called))))

(describe "ENVIRONMENTS section render"
  :var (rendered)
  (before-each
    (pio-project-config-invalidate)
    (spy-on 'pio--run-json-as
      :and-return-value
      (json-parse-string (pio-tests--fixture "pio-project-config.json")
        :object-type 'hash-table :array-type 'list
        :false-object nil :null-object nil))
    (cl-letf (((symbol-function 'pio-root)
                (lambda () "/Users/x/workspace/")))
      (pio-tests--with-temp-dir dir
        (write-region "" nil (expand-file-name "platformio.ini" dir))
        (cl-letf (((symbol-function 'pio-root)
                    (lambda () dir)))
          (with-temp-buffer
            (pio--render-envs)
            (setq rendered (buffer-string)))))))

  (it "renders an `ENVIRONMENTS' heading with the count"
    (expect rendered :to-match "\\`ENVIRONMENTS (4)"))

  (it "lists every env name, marking the default with a star"
    (expect rendered :to-render-substrings
      '("ceratina" "walter-iot" "esp32p4" "clay" "★"))))

(describe "pio--platform-display"
  (it "passes short platform names through unchanged"
    (expect (pio--platform-display "native")      :to-equal "native")
    (expect (pio--platform-display "espressif32") :to-equal "espressif32")
    (expect (pio--platform-display "ststm32")     :to-equal "ststm32"))

  (it "extracts the package basename from a git URL spec"
    (expect (pio--platform-display
              "https://github.com/pioarduino/platform-espressif32.git#develop")
      :to-equal "espressif32")
    (expect (pio--platform-display
              "https://github.com/platformio/platform-ststm32.git")
      :to-equal "ststm32"))

  (it "returns empty string for nil or empty input"
    (expect (pio--platform-display nil) :to-equal "")
    (expect (pio--platform-display "")  :to-equal ""))

  (it "joins list values (PlatformIO sometimes returns a single-element list)"
    (expect (pio--platform-display '("native")) :to-equal "native")))

(describe "pio-show-account-modeline"
  (it "defaults to nil (modeline segment off)"
    (expect (default-value 'pio-show-account-modeline) :to-be nil))

  (it "skips `pio--set-mode-line' when nil"
    (spy-on 'pio--set-mode-line)
    (spy-on 'pio-serial-devices :and-return-value [])
    (spy-on 'pio-envs)
    (let ((pio-show-account-modeline nil))
      (with-temp-buffer (pio--render)))
    (expect 'pio--set-mode-line :not :to-have-been-called))

  (it "calls `pio--set-mode-line' when t"
    (spy-on 'pio--set-mode-line)
    (spy-on 'pio-account-show :and-return-value (pio-tests--account))
    (spy-on 'pio-serial-devices :and-return-value [])
    (spy-on 'pio-envs)
    (let ((pio-show-account-modeline t))
      (with-temp-buffer (pio--render)))
    (expect 'pio--set-mode-line :to-have-been-called)))

(describe "dashboard keymap is RET-only (compile-multi owns task-running)"
  (it "binds RET to `pio-act-at-point'"
    (expect (lookup-key pio-mode-map (kbd "RET")) :to-equal #'pio-act-at-point))

  (it "inherits `g' and `?' from `special-mode'"
    (expect (lookup-key pio-mode-map (kbd "g")) :to-equal #'revert-buffer)
    (expect (lookup-key pio-mode-map (kbd "?")) :to-equal #'describe-mode))

  (it "leaves `r' and `c' without a custom binding"
    (dolist (key '("r" "c"))
      (expect (lookup-key pio-mode-map (kbd key)) :to-be nil))))

(describe "surfaces removed in favour of compile-multi"
  (it "no longer defines the `pio-dispatch' transient"
    (expect (fboundp 'pio-dispatch) :to-be nil))

  (it "no longer defines `pio-run-at-point'"
    (expect (fboundp 'pio-run-at-point) :to-be nil))

  (it "no longer defines `pio-run-target'"
    (expect (fboundp 'pio-run-target) :to-be nil)))

(describe "evil integration (self-contained in the mode, no eval-after-load)"
  (it "marks `pio-mode-map' as an evil overriding map when evil is available"
    (let (called-with)
      (cl-letf (((symbol-function 'evil-make-overriding-map)
                  (lambda (&rest args) (setq called-with args))))
        (with-temp-buffer (pio-mode)))
      (expect called-with :to-equal (list pio-mode-map 'normal)))))

(describe "compile-multi integration (hard dependency, registered directly)"
  (it "registers a pio task generator in `compile-multi-config'"
    (expect (assoc '(pio-in-project-p) compile-multi-config) :not :to-be nil)))

(describe "pio--nerd-icon (multi-set dispatch)"
  (it "dispatches on the `nf-SET-' prefix and returns a glyph for each set"
    (dolist (name '("nf-md-play" "nf-dev-embeddedc" "nf-fa-cloud_arrow_up"))
      (expect (string-empty-p (pio--nerd-icon name)) :to-be nil))))

(describe "pio-compile-multi-tasks (the seven .dir-locals pio tasks, per env)"
  (before-each
    (spy-on 'pio-root :and-return-value "/Users/x/workspace/")
    (spy-on 'pio--executable :and-return-value "pio")
    (spy-on 'pio-envs :and-return-value '("ceratina" "walter"))
    (spy-on 'pio-default-envs :and-return-value '("ceratina")))

  (it "generates the tasks only for `default_envs' by default"
    (let ((titles (mapcar #'car (pio-compile-multi-tasks))))
      (expect (seq-some (lambda (s) (string-search "ceratina" s)) titles) :to-be-truthy)
      (expect (seq-some (lambda (s) (string-search "walter" s)) titles) :not :to-be-truthy)))

  (it "expands to every env when `pio-compile-multi-all-envs' is set"
    (let* ((pio-compile-multi-all-envs t)
            (titles (mapcar #'car (pio-compile-multi-tasks))))
      (expect (seq-some (lambda (s) (string-search "walter" s)) titles) :to-be-truthy)))

  (it "reproduces exactly the seven pio tasks per env, in order"
    (let ((titles (mapcar #'car (pio-compile-multi-tasks))))
      (expect (length titles) :to-equal 7)
      (dolist (label '("pio run" "pio test" "pio test --without"
                        "pio run -t upload" "pio run -t compiledb"
                        "pio run -t uploadfs" "pio device monitor"))
        (expect (seq-some (lambda (s) (string-suffix-p label s)) titles) :to-be-truthy))))

  (it "emits all seven regardless of env metadata (no gating)"
    (spy-on 'pio-env-targets :and-return-value nil)
    (expect (length (pio-compile-multi-tasks)) :to-equal 7))

  (it "groups each task under its bare env name (no group glyph)"
    (let ((titles (mapcar #'car (pio-compile-multi-tasks))))
      (expect (seq-every-p (lambda (s) (string-prefix-p "ceratina" s)) titles) :to-be-truthy)))

  (it "emits compiledb once per env"
    (let* ((pio-compile-multi-all-envs t)
            (titles (mapcar #'car (pio-compile-multi-tasks))))
      (expect (seq-count (lambda (s) (string-search "compiledb" s)) titles) :to-equal 2)))

  (it "scopes each command to its env"
    (let* ((task  (car (pio-compile-multi-tasks)))
            (plist (cdr task)))
      (expect (car task) :to-match "pio run")
      (expect (plist-get plist :command) :to-match "--environment ceratina")))

  (it "defaults `pio-compile-multi-show-label' to nil (icon-only)"
    (expect (default-value 'pio-compile-multi-show-label) :to-be nil))

  (it "omits the `platformio' label by default, keeping the bee"
    (let ((ann (plist-get (cdr (car (pio-compile-multi-tasks))) :annotation)))
      (expect ann :not :to-match "platformio")
      (expect (string-search (nerd-icons-sucicon "nf-seti-platformio") ann)
        :to-be-truthy)))

  (it "shows the `platformio' label when show-label is non-nil"
    (let* ((pio-compile-multi-show-label t)
            (ann (plist-get (cdr (car (pio-compile-multi-tasks))) :annotation)))
      (expect ann :to-match "platformio")))

  (it "renders the `pio test' row with the exact .dir-locals devicon glyph"
    (let* ((titles (mapcar #'car (pio-compile-multi-tasks)))
            (row    (seq-find (lambda (s) (string-suffix-p "pio test" s)) titles)))
      (expect row :to-match (regexp-quote (nerd-icons-devicon "nf-dev-embeddedc"))))))

;;; pio-mode-tests.el ends here
