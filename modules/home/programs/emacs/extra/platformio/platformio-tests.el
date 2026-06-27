;;; platformio-tests.el --- Buttercup tests for platformio.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'ert-x)
(require 'platformio)

(buttercup-define-matcher-for-binary-function
    :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(describe "pio-p"
  (it "is non-nil when platformio.ini is present"
    (ert-with-temp-directory dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (expect (pio-p dir))))

  (it "is nil when platformio.ini is absent"
    (ert-with-temp-directory dir
      (expect (pio-p dir) :not :to-be-truthy))))

(describe "pio-root"
  (it "walks up from a subdirectory to find the project root"
    (ert-with-temp-directory dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (let ((subdir (expand-file-name "src" dir)))
        (make-directory subdir)
        (let ((default-directory subdir))
          (expect (pio-root) :to-be-file-equal dir)))))

  (it "returns nil when no project is found in the parent chain"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (pio-root) :not :to-be-truthy)))))

(describe "pio-in-project-p"
  (it "is non-nil inside a PlatformIO project"
    (ert-with-temp-directory dir
      (write-region "" nil (expand-file-name "platformio.ini" dir))
      (let ((default-directory dir))
        (expect (pio-in-project-p))))))

(describe "pio-name"
  (it "returns the directory name of the project root"
    (ert-with-temp-directory dir
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
    (ert-with-temp-directory dir
      (expect (pio-project-config dir) :not :to-be-truthy)))

  (it "delegates to pio--read-project-config and returns its result"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir '(("platformio" ("name" . "demo"))))
      (expect (pio-project-config dir)
              :to-equal '(("platformio" ("name" . "demo"))))))

  (it "caches the parsed config and skips reading on subsequent calls"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir '(("platformio" ("name" . "demo"))))
      (pio-project-config dir)
      (pio-project-config dir)
      (pio-project-config dir)
      (expect 'pio--read-project-config :to-have-been-called-times 1)))

  (it "re-reads when the platformio.ini mtime changes"
    (ert-with-temp-directory dir
      (let ((ini (expand-file-name "platformio.ini" dir)))
        (pio-tests--make-project dir '(("platformio" ("name" . "v1"))))
        (pio-project-config dir)
        (set-file-times ini (time-add (current-time) 5))
        (pio-project-config dir)
        (expect 'pio--read-project-config :to-have-been-called-times 2))))

  (it "invalidates a single project on demand"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir '(("platformio" ("name" . "demo"))))
      (pio-project-config dir)
      (pio-project-config-invalidate dir)
      (pio-project-config dir)
      (expect 'pio--read-project-config :to-have-been-called-times 2))))

(describe "pio-envs"
  (before-each (pio-project-config-invalidate))

  (it "extracts env: section names in declaration order"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("platformio"      ("default_envs" "release"))
         ("env:release"     ("build_type"   . "release"))
         ("env:debug"       ("build_type"   . "debug"))
         ("env:custom_plank" ("board"       . "custom"))))
      (expect (pio-envs dir)
              :to-equal '("release" "debug" "custom_plank"))))

  (it "ignores non-env sections like [platformio] and [embedded]"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("platformio" ("default_envs" "release"))
         ("embedded"   ("framework" . "arduino"))
         ("env:dev"    ("board" . "esp32dev"))))
      (expect (pio-envs dir) :to-equal '("dev"))))

  (it "returns nil when no env: sections exist"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("platformio" ("name" . "demo"))))
      (expect (pio-envs dir) :not :to-be-truthy)))

  (it "returns nil when platformio.ini is absent"
    (ert-with-temp-directory dir
      (expect (pio-envs dir) :not :to-be-truthy))))

(describe "pio-default-envs"
  (before-each
    (pio-project-config-invalidate)
    (setenv "PLATFORMIO_DEFAULT_ENVS" nil))

  (it "returns the default_envs list from [platformio]"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("platformio" ("default_envs" "release" "debug"))))
      (expect (pio-default-envs dir) :to-equal '("release" "debug"))))

  (it "handles a single-element default_envs list"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("platformio" ("default_envs" "release"))))
      (expect (pio-default-envs dir) :to-equal '("release"))))

  (it "returns nil when default_envs is absent"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("platformio" ("name" . "demo"))))
      (expect (pio-default-envs dir) :not :to-be-truthy)))

  (it "honors PLATFORMIO_DEFAULT_ENVS env var over the config value"
    (ert-with-temp-directory dir
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

(defconst pio-tests--system-info-json
  "{\"core_version\":{\"title\":\"PlatformIO Core\",\"value\":\"6.1.19\"},\
\"python_version\":{\"title\":\"Python\",\"value\":\"3.13.7-final.0\"},\
\"core_dir\":{\"title\":\"PlatformIO Core Directory\",\"value\":\"/Users/x/.platformio\"},\
\"platformio_exe\":{\"title\":\"PlatformIO Core Executable\",\"value\":\"/usr/local/bin/pio\"}}")

(describe "pio-system-info accessors"
  (before-each
    (setq pio--system-info-cache nil)
    (spy-on 'shell-command-to-string
            :and-return-value pio-tests--system-info-json))

  (it "parses `pio system info' JSON into title+value plists"
    (expect (pio-core-version)
            :to-equal '(:title "PlatformIO Core" :value "6.1.19"))
    (expect (pio-core-dir)
            :to-equal '(:title "PlatformIO Core Directory"
                        :value "/Users/x/.platformio"))
    (expect (pio-platformio-exe)
            :to-equal '(:title "PlatformIO Core Executable"
                        :value "/usr/local/bin/pio")))

  (it "caches `pio system info' across calls"
    (pio-core-version)
    (pio-python-version)
    (pio-platformio-exe)
    (expect 'shell-command-to-string :to-have-been-called-times 1))

  (it "re-fetches after `pio-system-info-invalidate'"
    (pio-core-version)
    (pio-system-info-invalidate)
    (pio-core-version)
    (expect 'shell-command-to-string :to-have-been-called-times 2))

  (it "returns nil for unknown fields"
    (expect (pio-package-tool-nums) :not :to-be-truthy)))

(describe "pio--detect-executables"
  (it "finds pio and platformio across PATH entries"
    (ert-with-temp-directory dir1
      (ert-with-temp-directory dir2
        (let ((pio1 (expand-file-name "pio" dir1))
              (pio2 (expand-file-name "platformio" dir2)))
          (write-region "" nil pio1)
          (write-region "" nil pio2)
          (set-file-modes pio1 #o755)
          (set-file-modes pio2 #o755)
          (with-environment-variables
              (("PATH" (format "%s%s%s" dir1 path-separator dir2)))
            (expect (pio--detect-executables)
                    :to-have-same-items-as (list pio1 pio2)))))))

  (it "returns a single entry when only one binary is on PATH"
    (ert-with-temp-directory dir
      (let ((pio (expand-file-name "pio" dir)))
        (write-region "" nil pio)
        (set-file-modes pio #o755)
        (with-environment-variables (("PATH" dir))
          (expect (pio--detect-executables) :to-equal (list pio)))))))

(describe "pio--warn-multiple-executables"
  (before-each
    (setq pio--multiple-executables-warned nil)
    (spy-on 'display-warning))

  (it "calls `display-warning' when more than one executable is found"
    (spy-on 'pio--detect-executables
            :and-return-value '("/a/pio" "/b/platformio"))
    (pio--warn-multiple-executables)
    (expect 'display-warning :to-have-been-called-times 1)
    (let ((args (spy-calls-args-for 'display-warning 0)))
      (expect (nth 0 args) :to-equal 'pio)
      (expect (nth 1 args) :to-match "Multiple PlatformIO executables")))

  (it "does not warn when only one executable exists"
    (spy-on 'pio--detect-executables :and-return-value '("/a/pio"))
    (pio--warn-multiple-executables)
    (expect 'display-warning :not :to-have-been-called))

  (it "only warns once per session"
    (spy-on 'pio--detect-executables
            :and-return-value '("/a/pio" "/b/platformio"))
    (pio--warn-multiple-executables)
    (pio--warn-multiple-executables)
    (pio--warn-multiple-executables)
    (expect 'display-warning :to-have-been-called-times 1)))

(describe "pio--read-key"
  (before-each (pio-project-config-invalidate))

  (it "reads a key from a named section"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("env:dev" ("board"    . "esp32dev")
                    ("platform" . "espressif32"))))
      (expect (pio--read-key "env:dev" "board"    dir) :to-equal "esp32dev")
      (expect (pio--read-key "env:dev" "platform" dir) :to-equal "espressif32")))

  (it "does not read keys outside the named section"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("env:a" ("board"     . "esp32dev"))
         ("env:b" ("framework" . "arduino"))))
      (expect (pio--read-key "env:a" "framework" dir) :not :to-be-truthy)
      (expect (pio--read-key "env:b" "board"     dir) :not :to-be-truthy)))

  (it "returns nil when the section is absent"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir '(("env:dev" ("board" . "esp32dev"))))
      (expect (pio--read-key "env:missing" "board" dir) :not :to-be-truthy)))

  (it "returns nil when the section exists but the key does not"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir '(("env:dev" ("board" . "esp32dev"))))
      (expect (pio--read-key "env:dev" "framework" dir) :not :to-be-truthy)))

  (it "returns native typed values (numbers, lists, booleans)"
    (ert-with-temp-directory dir
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
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("env:walter" ("board"    . "esp32dev")
                       ("platform" . "espressif32"))))
      (expect (pio-env-board "walter" dir) :to-equal "esp32dev"))))

(describe "pio-env-platform"
  (before-each (pio-project-config-invalidate))
  (it "reads the platform key from the [env:ENV] section"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("env:walter" ("board"    . "esp32dev")
                       ("platform" . "espressif32"))))
      (expect (pio-env-platform "walter" dir) :to-equal "espressif32"))))

(describe "pio-env-framework"
  (before-each (pio-project-config-invalidate))
  (it "reads the framework key from the [env:ENV] section"
    (ert-with-temp-directory dir
      (pio-tests--make-project dir
       '(("env:walter" ("board"     . "esp32dev")
                       ("framework" "arduino"))))
      (expect (pio-env-framework "walter" dir) :to-equal '("arduino")))))

(describe "vterm kill-buffer contract"
  (it "killing a vterm buffer kills the underlying subprocess"
    ;; Documents the contract `pio-device-monitor' relies on: when the
    ;; vterm buffer is killed, vterm tears down the PTY and the child
    ;; process receives SIGHUP. A long-running `sleep' stands in for pio
    ;; so the test is hermetic (no pio, no serial device required).
    (assume (and (fboundp 'vterm) (executable-find "sleep"))
            "vterm or sleep unavailable")
    (let ((vterm-shell "sleep 60")
          (vterm-buffer-name "*pio-test-vterm-lifecycle*")
          (kill-buffer-query-functions nil))
      (when (get-buffer vterm-buffer-name) (kill-buffer vterm-buffer-name))
      (vterm)
      (let* ((buffer (get-buffer vterm-buffer-name))
             (proc   (get-buffer-process buffer)))
        (expect (process-live-p proc) :to-be-truthy)
        (kill-buffer buffer)
        (sleep-for 0.3)
        (expect (process-live-p proc) :not :to-be-truthy)))))

(describe "pio-device-monitor"
  (it "passes the resolved command to vterm via `vterm-shell'"
    (let ((pio-executable "pio")
          (pio-monitor-profiles
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
      (expect captured-name :to-equal "*pio:monitor:/dev/cu.usbmodem1101*"))))

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

  (it "propertizes the SERIAL cell with success and the PORT cell with warning"
    (spy-on 'pio-serial-devices :and-return-value
            (vector (pio-tests--make-device
                     "/dev/cu.x" "x"
                     "VID:PID=0000:0000 SER=AB:CD")))
    (let* ((row         (cadr (car (pio--device-list-entries))))
           (serial-cell (aref row 0))
           (port-cell   (aref row 2)))
      (expect (get-text-property 0 'face serial-cell) :to-equal 'success)
      (expect (get-text-property 0 'face port-cell)   :to-equal 'warning)))

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
      (expect (length (pio--device-list-entries)) :to-equal 2))))

(describe "pio-device-list-monitor"
  (before-each
    (spy-on 'pio-default-envs   :and-return-value nil)
    (spy-on 'pio-device-monitor))

  (it "passes the port at point to `pio-device-monitor'"
    (with-temp-buffer
      (pio-device-list-mode)
      (setq tabulated-list-entries
            '(("/dev/cu.usbmodem1101"
               ["ABC" "303A:1001" "/dev/cu.usbmodem1101" "1-1" "x"])))
      (tabulated-list-print)
      (goto-char (point-min))
      (pio-device-list-monitor)
      (expect 'pio-device-monitor
              :to-have-been-called-with :port "/dev/cu.usbmodem1101")))

  (it "is a no-op when point is not on a device row"
    (with-temp-buffer
      (pio-device-list-mode)
      (setq tabulated-list-entries nil)
      (tabulated-list-print)
      (pio-device-list-monitor)
      (expect 'pio-device-monitor :not :to-have-been-called))))

(describe "nerd-icons registration"
  (it "registers `pio-mode' with `nf-md-chip' in `nerd-icons-mode-icon-alist'"
    (require 'nerd-icons)
    (let ((entry (assq 'pio-mode nerd-icons-mode-icon-alist)))
      (expect entry :to-be-truthy)
      (expect (nth 1 entry) :to-equal 'nerd-icons-mdicon)
      (expect (nth 2 entry) :to-equal "nf-md-chip"))))

;;; Account

(defconst pio-tests--account-json
  "{
    \"profile\": {
      \"username\": \"alice\",
      \"email\": \"alice@example.com\",
      \"firstname\": \"Alice\",
      \"lastname\": \"Example\"
    },
    \"packages\": [
      {\"name\": \"pkg-a\", \"title\": \"Package A\",
       \"description\": \"first package\"},
      {\"name\": \"pkg-b\", \"title\": \"Package B\",
       \"description\": \"second package\"}
    ],
    \"subscriptions\": [],
    \"user_id\": \"00000000-0000-0000-0000-000000000000\",
    \"expire_at\": 1783205299
  }")

(defun pio-tests--account ()
  "Return the sample account fixture parsed into the shape `pio-account-show' yields."
  (json-parse-string pio-tests--account-json
                     :object-type 'hash-table
                     :array-type  'list
                     :false-object nil
                     :null-object  nil))

(describe "pio--run-json"
  (it "signals `pio-exec-error' on non-zero exit"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (insert "boom\n") 1)))
      (expect (pio--run-json "wat") :to-throw 'pio-exec-error)))

  (it "signals `pio-parse-error' when stdout is not JSON"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (insert "not json {[") 0)))
      (expect (pio--run-json "account" "show" "--json-output")
              :to-throw 'pio-parse-error)))

  (it "subclasses can be caught as the generic `pio-error'"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (insert "boom") 1)))
      (expect (pio--run-json "wat") :to-throw 'pio-error))))

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

  (it "extracts the account expiry epoch"
    (expect (pio-account-expire-at account) :to-equal 1783205299)))

(describe "pio--render"
  :var (rendered)
  (before-each
    (spy-on 'pio-core-version
            :and-return-value '(:title "PlatformIO Core" :value "6.1.19"))
    (with-temp-buffer
      (pio--render (pio-tests--account))
      (setq rendered (buffer-string))))

  (it "renders a PROFILE heading and its fields"
    (expect rendered :to-match "^PROFILE")
    (expect rendered :to-match "alice")
    (expect rendered :to-match "Alice Example")
    (expect rendered :to-match "alice@example\\.com")
    (expect rendered :to-match "00000000-"))

  (it "renders a PACKAGES section with the count and titles"
    (expect rendered :to-match "^PACKAGES (2)")
    (expect rendered :to-match "Package A")
    (expect rendered :to-match "first package")
    (expect rendered :to-match "Package B")
    (expect rendered :to-match "second package"))

  (it "renders the SUBSCRIPTIONS heading as `none' when the list is empty"
    (expect rendered :to-match "SUBSCRIPTIONS (none)")))

(describe "pio--set-mode-line"
  (it "sets `mode-name' to include core version + username"
    (spy-on 'pio-core-version
            :and-return-value '(:title "PlatformIO Core" :value "6.1.19"))
    (with-temp-buffer
      (pio--set-mode-line (pio-tests--account))
      (let ((joined (apply #'concat mode-name)))
        (expect joined :to-match "v6\\.1\\.19")
        (expect joined :to-match "alice")))))

(describe "pio (interactive entry point)"
  (before-each
    (pio-account-invalidate)
    (spy-on 'pio--run-json
            :and-call-fake (lambda (&rest _) (pio-tests--account)))
    (spy-on 'pio-core-version
            :and-return-value '(:title "PlatformIO Core" :value "6.1.19"))
    (spy-on 'pop-to-buffer))

  (after-each
    (when (get-buffer pio-buffer-name)
      (let (kill-buffer-query-functions)
        (kill-buffer pio-buffer-name))))

  (it "creates a `*pio*' buffer in `pio-mode'"
    (pio)
    (let ((buffer (get-buffer pio-buffer-name)))
      (expect (buffer-live-p buffer) :to-be-truthy)
      (with-current-buffer buffer
        (expect major-mode :to-equal 'pio-mode)
        (expect (buffer-string) :to-match "PROFILE"))))

  (it "is revertable via `revert-buffer'"
    (pio)
    (with-current-buffer pio-buffer-name
      (let ((before (buffer-string)))
        (revert-buffer nil t)
        (expect (buffer-string) :to-equal before)))))

;;; platformio-tests.el ends here
