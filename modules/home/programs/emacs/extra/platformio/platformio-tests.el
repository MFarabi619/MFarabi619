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

(describe "pio-envs"
  (it "extracts all [env:X] section names in order"
    (ert-with-temp-directory dir
      (write-region "[platformio]\ndefault_envs = release\n\n[env:release]\nbuild_type = release\n\n[env:debug]\nbuild_type = debug\n\n[env:custom_plank]\nboard = custom\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-envs dir)
              :to-equal '("release" "debug" "custom_plank"))))

  (it "returns nil when no [env:X] sections exist"
    (ert-with-temp-directory dir
      (write-region "[platformio]\n" nil (expand-file-name "platformio.ini" dir))
      (expect (pio-envs dir) :not :to-be-truthy)))

  (it "returns nil when platformio.ini is absent"
    (ert-with-temp-directory dir
      (expect (pio-envs dir) :not :to-be-truthy))))

(describe "pio-default-envs"
  (before-each
    (setenv "PLATFORMIO_DEFAULT_ENVS" nil))

  (it "splits comma- or space-separated default_envs from [platformio]"
    (ert-with-temp-directory dir
      (write-region "[platformio]\ndefault_envs = release, debug\n\n[env:release]\n[env:debug]\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-default-envs dir)
              :to-equal '("release" "debug"))))

  (it "handles a single default env"
    (ert-with-temp-directory dir
      (write-region "[platformio]\ndefault_envs = release\n\n[env:release]\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-default-envs dir) :to-equal '("release"))))

  (it "returns nil when default_envs is absent"
    (ert-with-temp-directory dir
      (write-region "[platformio]\nfoo = bar\n" nil (expand-file-name "platformio.ini" dir))
      (expect (pio-default-envs dir) :not :to-be-truthy)))

  (it "does not read default_envs from inside an [env:X] section"
    (ert-with-temp-directory dir
      (write-region "[platformio]\n\n[env:release]\ndefault_envs = wrong\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-default-envs dir) :not :to-be-truthy)))

  (it "honors PLATFORMIO_DEFAULT_ENVS env var over the config value"
    (ert-with-temp-directory dir
      (write-region "[platformio]\ndefault_envs = from-config\n"
                    nil (expand-file-name "platformio.ini" dir))
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
  (before-each (setq pio--system-info-cache nil))

  (it "parses `pio system info' JSON into title+value plists"
    (cl-letf (((symbol-function 'shell-command-to-string)
               (lambda (&rest _) pio-tests--system-info-json)))
      (expect (pio-core-version)
              :to-equal '(:title "PlatformIO Core" :value "6.1.19"))
      (expect (pio-core-dir)
              :to-equal '(:title "PlatformIO Core Directory"
                          :value "/Users/x/.platformio"))
      (expect (pio-platformio-exe)
              :to-equal '(:title "PlatformIO Core Executable"
                          :value "/usr/local/bin/pio"))))

  (it "caches `pio system info' across calls"
    (let ((call-count 0))
      (cl-letf (((symbol-function 'shell-command-to-string)
                 (lambda (&rest _)
                   (cl-incf call-count)
                   pio-tests--system-info-json)))
        (pio-core-version)
        (pio-python-version)
        (pio-platformio-exe)
        (expect call-count :to-equal 1))))

  (it "re-fetches after `pio-system-info-invalidate'"
    (let ((call-count 0))
      (cl-letf (((symbol-function 'shell-command-to-string)
                 (lambda (&rest _)
                   (cl-incf call-count)
                   pio-tests--system-info-json)))
        (pio-core-version)
        (pio-system-info-invalidate)
        (pio-core-version)
        (expect call-count :to-equal 2))))

  (it "returns nil for unknown fields"
    (cl-letf (((symbol-function 'shell-command-to-string)
               (lambda (&rest _) pio-tests--system-info-json)))
      (expect (pio-package-tool-nums) :not :to-be-truthy))))

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
  (before-each (setq pio--multiple-executables-warned nil))

  (it "calls `display-warning' when more than one executable is found"
    (cl-letf* ((warnings nil)
               ((symbol-function 'pio--detect-executables)
                (lambda () '("/a/pio" "/b/platformio")))
               ((symbol-function 'display-warning)
                (lambda (type message &rest _) (push (cons type message) warnings))))
      (pio--warn-multiple-executables)
      (expect (length warnings) :to-equal 1)
      (expect (caar warnings) :to-equal 'pio)
      (expect (cdar warnings) :to-match "Multiple PlatformIO executables")))

  (it "does not warn when only one executable exists"
    (cl-letf* ((called nil)
               ((symbol-function 'pio--detect-executables)
                (lambda () '("/a/pio")))
               ((symbol-function 'display-warning)
                (lambda (&rest _) (setq called t))))
      (pio--warn-multiple-executables)
      (expect called :not :to-be-truthy)))

  (it "only warns once per session"
    (cl-letf* ((call-count 0)
               ((symbol-function 'pio--detect-executables)
                (lambda () '("/a/pio" "/b/platformio")))
               ((symbol-function 'display-warning)
                (lambda (&rest _) (cl-incf call-count))))
      (pio--warn-multiple-executables)
      (pio--warn-multiple-executables)
      (pio--warn-multiple-executables)
      (expect call-count :to-equal 1))))

(describe "pio--read-key"
  (it "reads a key from a named section"
    (ert-with-temp-directory dir
      (write-region "[env:dev]\nboard = esp32dev\nplatform = espressif32\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio--read-key "env:dev" "board" dir) :to-equal "esp32dev")
      (expect (pio--read-key "env:dev" "platform" dir) :to-equal "espressif32")))

  (it "does not read keys outside the named section"
    (ert-with-temp-directory dir
      (write-region "[env:a]\nboard = esp32dev\n\n[env:b]\nframework = arduino\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio--read-key "env:a" "framework" dir) :not :to-be-truthy)
      (expect (pio--read-key "env:b" "board" dir) :not :to-be-truthy)))

  (it "returns nil when the section is absent"
    (ert-with-temp-directory dir
      (write-region "[env:dev]\nboard = esp32dev\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio--read-key "env:missing" "board" dir) :not :to-be-truthy)))

  (it "returns nil when the section exists but the key does not"
    (ert-with-temp-directory dir
      (write-region "[env:dev]\nboard = esp32dev\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio--read-key "env:dev" "framework" dir) :not :to-be-truthy)))

  (it "handles the last section in the file (no trailing section header)"
    (ert-with-temp-directory dir
      (write-region "[platformio]\ndefault_envs = release\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio--read-key "platformio" "default_envs" dir)
              :to-equal "release"))))

(describe "pio-env-board"
  (it "reads the board key from the [env:ENV] section"
    (ert-with-temp-directory dir
      (write-region "[env:walter]\nboard = esp32dev\nplatform = espressif32\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-env-board "walter" dir) :to-equal "esp32dev"))))

(describe "pio-env-platform"
  (it "reads the platform key from the [env:ENV] section"
    (ert-with-temp-directory dir
      (write-region "[env:walter]\nboard = esp32dev\nplatform = espressif32\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-env-platform "walter" dir) :to-equal "espressif32"))))

(describe "pio-env-framework"
  (it "reads the framework key from the [env:ENV] section"
    (ert-with-temp-directory dir
      (write-region "[env:walter]\nboard = esp32dev\nframework = arduino\n"
                    nil (expand-file-name "platformio.ini" dir))
      (expect (pio-env-framework "walter" dir) :to-equal "arduino"))))

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
  (it "splits hwid into SERIAL, VID:PID, LOCATION columns and puts Description last"
    (cl-letf (((symbol-function 'pio-serial-devices)
               (lambda ()
                 (vector
                  (pio-tests--make-device
                   "/dev/cu.usbmodem1101" "USB JTAG/serial debug unit"
                   "USB VID:PID=303A:1001 SER=CC:BA:97:16:2B:68 LOCATION=1-1")))))
      (let ((entries (pio--device-list-entries)))
        (expect (length entries) :to-equal 1)
        (expect (car (car entries)) :to-equal "/dev/cu.usbmodem1101")
        (expect (pio-tests--row-strings (car entries))
                :to-equal
                '("/dev/cu.usbmodem1101"
                  "CC:BA:97:16:2B:68"
                  "303A:1001"
                  "1-1"
                  "USB JTAG/serial debug unit")))))

  (it "leaves hwid columns empty when the hwid string is missing"
    (cl-letf (((symbol-function 'pio-serial-devices)
               (lambda ()
                 (vector (pio-tests--make-device "/dev/cu.x" nil "VID:PID=0000:0000")))))
      (expect (pio-tests--row-strings (car (pio--device-list-entries)))
              :to-equal '("/dev/cu.x" "" "0000:0000" "" ""))))

  (it "propertizes the Port cell with the success face"
    (cl-letf (((symbol-function 'pio-serial-devices)
               (lambda ()
                 (vector (pio-tests--make-device "/dev/cu.x" "x" "VID:PID=0000:0000")))))
      (let* ((entries (pio--device-list-entries))
             (port-cell (aref (cadr (car entries)) 0)))
        (expect (get-text-property 0 'face port-cell) :to-equal 'success))))

  (it "hides devices whose hwid is \"n/a\" when `hide-unidentified' is t"
    (cl-letf (((symbol-function 'pio-serial-devices)
               (lambda ()
                 (vector
                  (pio-tests--make-device "/dev/cu.Bluetooth-Incoming-Port" "n/a" "n/a")
                  (pio-tests--make-device "/dev/cu.PowerbeatsPro"           "n/a" "n/a")
                  (pio-tests--make-device "/dev/cu.debug-console"           "n/a" "n/a")
                  (pio-tests--make-device "/dev/cu.usbmodem1101" "USB JTAG" "VID:PID=303A:1001")))))
      (let* ((pio-device-list-hide-unidentified t)
             (pio-device-list-exclude-regexps nil)
             (entries (pio--device-list-entries)))
        (expect (length entries) :to-equal 1)
        (expect (car (car entries)) :to-equal "/dev/cu.usbmodem1101"))))

  (it "filters by `exclude-regexps' on top of the heuristic"
    (cl-letf (((symbol-function 'pio-serial-devices)
               (lambda ()
                 (vector
                  (pio-tests--make-device "/dev/cu.usbserial-FTDI"  "FTDI" "VID:PID=0403:6001")
                  (pio-tests--make-device "/dev/cu.usbmodem1101"    "USB JTAG" "VID:PID=303A:1001")))))
      (let* ((pio-device-list-hide-unidentified t)
             (pio-device-list-exclude-regexps '("FTDI"))
             (entries (pio--device-list-entries)))
        (expect (length entries) :to-equal 1)
        (expect (car (car entries)) :to-equal "/dev/cu.usbmodem1101"))))

  (it "shows every device when both filters are disabled"
    (cl-letf (((symbol-function 'pio-serial-devices)
               (lambda ()
                 (vector
                  (pio-tests--make-device "/dev/cu.Bluetooth-Incoming-Port" "n/a" "n/a")
                  (pio-tests--make-device "/dev/cu.usbmodem1101" "x" "y")))))
      (let ((pio-device-list-hide-unidentified nil)
            (pio-device-list-exclude-regexps nil))
        (expect (length (pio--device-list-entries)) :to-equal 2)))))

(describe "pio-device-list-monitor"
  (it "passes the port at point to `pio-device-monitor'"
    (let (captured)
      (cl-letf (((symbol-function 'pio-device-monitor)
                 (lambda (&rest args) (setq captured args))))
        (with-temp-buffer
          (pio-device-list-mode)
          (setq tabulated-list-entries
                '(("/dev/cu.usbmodem1101"
                   ["/dev/cu.usbmodem1101" "ABC" "303A:1001" "1-1" "x"])))
          (tabulated-list-print)
          (goto-char (point-min))
          (pio-device-list-monitor)
          (expect captured :to-equal '(:port "/dev/cu.usbmodem1101"))))))

  (it "is a no-op when point is not on a device row"
    (let (called)
      (cl-letf (((symbol-function 'pio-device-monitor)
                 (lambda (&rest _) (setq called t))))
        (with-temp-buffer
          (pio-device-list-mode)
          (setq tabulated-list-entries nil)
          (tabulated-list-print)
          (pio-device-list-monitor)
          (expect called :not :to-be-truthy))))))

;;; platformio-tests.el ends here
