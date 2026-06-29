;;; mcumgr-tests.el --- Buttercup tests for mcumgr.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; WIP

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'mcumgr)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

;;; Fixtures

(defconst mcumgr-tests--fixtures-dir
  (expand-file-name "fixtures/"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the `mcumgr-<command>.json' fixtures.
Captured from real `mcumgrctl' output.")

(defun mcumgr-tests--fixture (name)
  "Return the contents of `fixtures/NAME' as a string.
Safe to call from inside spec bodies; the directory is resolved at load time."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name mcumgr-tests--fixtures-dir))
    (buffer-string)))

(defconst mcumgr-tests--fixture-manifest
  '(;; host-side: USB/serial enumeration (no transport required)
     ("mcumgr-usb-serial.json"              "--usb-serial" "--json")
     ("mcumgr-serial-ports.json"            "--serial"     "--json")
     ;; device: image group
     ("mcumgr-image-get-state.json"         "image" "get-state"         "--json")
     ("mcumgr-image-slot-info.json"         "image" "slot-info"         "--json")
     ;; device: os group
     ("mcumgr-os-task-statistics.json"      "os" "task-statistics"      "--json")
     ("mcumgr-os-mcumgr-parameters.json"    "os" "mcumgr-parameters"    "--json")
     ("mcumgr-os-application-info.json"     "os" "application-info"     "--json")
     ("mcumgr-os-bootloader-info.json"      "os" "bootloader-info"      "--json")
     ;; device: stats group
     ("mcumgr-stats-list-groups.json"       "stats" "list-groups"       "--json")
     ;; device: enum group
     ("mcumgr-enum-list-groups.json"        "enum" "list-groups"        "--json")
     ("mcumgr-enum-show-group-details.json" "enum" "show-group-details" "--json")
     ;; device: fs group
     ("mcumgr-fs-status.json"               "fs" "status"   "/SD:/www/index.html" "--json")
     ("mcumgr-fs-checksum.json"             "fs" "checksum" "/SD:/www/index.html" "--json"))
  "Map each `fixtures/FILE.json' to the `mcumgrctl' args that produced it.
Host-side entries start with `--usb-serial' or `--serial'; all others need a
transport.  The auto-generated suite uses this for parse-cleanly and live-drift
specs without per-command boilerplate.")

(defcustom mcumgr-tests-transport nil
  "Transport plist for live-device freshness specs, e.g. (:udp \"10.0.0.172\").
Left nil to skip all device-side drift checks."
  :type '(choice (const :tag "Skip" nil) sexp)
  :group 'mcumgr)

(defun mcumgr-tests--run-cli (&rest args)
  "Run `mcumgrctl ARGS', returning stdout as a string; error on non-zero exit."
  (with-temp-buffer
    (let ((exit (apply #'call-process "mcumgrctl" nil t nil args)))
      (unless (zerop exit)
        (error "Mcumgrctl %s failed (exit %d): %s"
          (string-join args " ") exit (buffer-string)))
      (buffer-string))))

;;; Inline plain-text fixtures (not JSON; not in the manifest)

(defconst mcumgr-tests--ping-success-output "Device alive and responsive.\n")
(defconst mcumgr-tests--ping-failure-output "Error: connection timed out\n")

;;; Test helpers

(defmacro mcumgr-tests--stub-run (output &rest body)
  "Stub `mcumgr--run' to return OUTPUT and capture its args during BODY."
  (declare (indent 1))
  `(let (captured-args)
     (ignore captured-args)
     (cl-letf (((symbol-function 'mcumgr--run)
                 (lambda (&rest args) (setq captured-args args) ,output)))
       ,@body)))

(defmacro mcumgr-tests--with-shell (&rest body)
  "Override `mcumgr--executable' to /bin/sh for BODY.
Logging is disabled so the shared `*mcumgr*' buffer is not polluted."
  (declare (indent 0))
  `(let ((mcumgr-log-enabled nil))
     (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/sh")))
       ,@body)))

(defun mcumgr-tests--wait (proc &optional done-p)
  "Pump the event loop until PROC exits and DONE-P (when given) is non-nil.
Waiting on `process-live-p' alone is insufficient: a process's sentinel
runs on a later event-loop turn, so sentinel effects (`:on-exit', buffer
cleanup, the final `:on-output' line) may not have happened yet when the
process is already dead.  DONE-P expresses that post-condition.  A timeout
guards against a sentinel that never fires."
  (with-timeout (5 (error "Mcumgr async wait timed out"))
    (while (or (process-live-p proc) (and done-p (not (funcall done-p))))
      (accept-process-output nil 0.05))))

;;; Auto-generated fixture specs

(describe "every captured fixture"
  (dolist (entry mcumgr-tests--fixture-manifest)
    (let* ((name    (car entry))
            (args    (cdr entry))
            (host-p  (member (car args) '("--usb-serial" "--serial")))
            (cli-str (format "mcumgrctl %s" (string-join args " "))))

      (it (format "%s parses as non-empty JSON" name)
        (let ((content (mcumgr-tests--fixture name)))
          (expect (length content) :to-be-greater-than 0)
          (expect (json-parse-string content) :not :to-throw)))

      (it (format "stays in sync with `%s' on the running machine" cli-str)
        (assume (executable-find "mcumgrctl") "mcumgrctl not on PATH")
        (unless host-p
          (assume mcumgr-tests-transport
            "`mcumgr-tests-transport' unset (device transport required)"))
        (let* ((full-args (if host-p
                            args
                            (append (mcumgr--transport-args mcumgr-tests-transport) args)))
                (raw (apply #'mcumgr-tests--run-cli full-args)))
          (expect (length raw) :to-be-greater-than 0)
          (expect (json-parse-string raw) :not :to-throw))))))

;;; Error handling

(describe "mcumgr--run error handling"
  (it "raises `mcumgr-exec-error' on non-zero exit, carrying full context"
    (cl-letf (((symbol-function 'mcumgr--call)
                (lambda (_exe _args)
                  (list 1 "partial stdout" "Error: connection timed out\n"))))
      (condition-case err
        (progn (mcumgr--run "--udp" "10.0.0.1") (error "Expected to signal"))
        (mcumgr-exec-error
          (let ((data (cdr err)))
            (expect (plist-get data :exit-code) :to-equal 1)
            (expect (plist-get data :stdout)    :to-equal "partial stdout")
            (expect (plist-get data :stderr)    :to-match "connection timed out")
            (expect (plist-get data :args)      :to-equal '("--udp" "10.0.0.1")))))))

  (it "returns stdout cleanly on zero exit"
    (cl-letf (((symbol-function 'mcumgr--call)
                (lambda (_exe _args) (list 0 "hello\n" ""))))
      (expect (mcumgr--run "x") :to-equal "hello\n"))))

(describe "mcumgr--run-json error handling"
  (it "raises `mcumgr-parse-error' when stdout is not valid JSON, carrying context"
    (cl-letf (((symbol-function 'mcumgr--run)
                (lambda (&rest _) "this is not json")))
      (condition-case err
        (progn (mcumgr--run-json "--bogus") (error "Expected to signal"))
        (mcumgr-parse-error
          (let ((data (cdr err)))
            (expect (plist-get data :output) :to-equal "this is not json")
            (expect (plist-get data :args)   :to-equal '("--bogus"))
            (expect (plist-get data :error)  :to-be-truthy))))))

  (it "propagates `mcumgr-exec-error' unchanged from the underlying `mcumgr--run'"
    (cl-letf (((symbol-function 'mcumgr--run)
                (lambda (&rest _) (signal 'mcumgr-exec-error
                                    '(:exit-code 1 :stderr "boom")))))
      (expect (mcumgr--run-json "x") :to-throw 'mcumgr-exec-error))))

;;; Async infrastructure

(describe "mcumgr-run-async"
  (it "calls :on-exit with (exit-code stdout stderr) on termination"
    (mcumgr-tests--with-shell
      (let (result)
        (let ((proc (mcumgr-run-async
                      '("-c" "echo out; echo err >&2; exit 3")
                      :on-exit (lambda (code o e)
                                 (setq result (list code o e))))))
          (mcumgr-tests--wait proc (lambda () result))
          (expect (nth 0 result) :to-equal 3)
          (expect (nth 1 result) :to-match "out")
          (expect (nth 2 result) :to-match "err")))))

  (it "calls :on-output for each complete stdout line"
    (mcumgr-tests--with-shell
      (let (lines)
        (let ((proc (mcumgr-run-async
                      '("-c" "echo a; echo b; echo c")
                      :on-output (lambda (line) (push line lines)))))
          (mcumgr-tests--wait proc (lambda () (= (length lines) 3)))
          (expect (nreverse lines) :to-equal '("a" "b" "c"))))))

  (it "kills the underlying buffers when the process exits"
    (mcumgr-tests--with-shell
      (let* ((before (length (buffer-list)))
              (proc   (mcumgr-run-async '("-c" "echo done"))))
        (mcumgr-tests--wait proc (lambda () (= (length (buffer-list)) before)))
        (expect (length (buffer-list)) :to-equal before)))))

(describe "mcumgr-task-wait"
  (it "blocks until exit and returns stdout"
    (mcumgr-tests--with-shell
      (expect (mcumgr-task-wait
                (mcumgr-run-async '("-c" "echo hello")))
        :to-equal "hello\n")))

  (it "signals `mcumgr-exec-error' on non-zero exit with full context"
    (mcumgr-tests--with-shell
      (let ((proc (mcumgr-run-async
                    '("-c" "echo out; echo boom >&2; exit 5"))))
        (condition-case err
          (progn (mcumgr-task-wait proc) (error "Expected to signal"))
          (mcumgr-exec-error
            (let ((data (cdr err)))
              (expect (plist-get data :exit-code) :to-equal 5)
              (expect (plist-get data :stderr)    :to-match "boom")))))))

  (it "kills the process and signals on timeout"
    (mcumgr-tests--with-shell
      (let* ((proc  (mcumgr-run-async '("-c" "sleep 5")))
              (start (float-time))
              error-data)
        (condition-case err
          (mcumgr-task-wait proc 0.15)
          (mcumgr-exec-error (setq error-data (cdr err))))
        (expect (- (float-time) start) :to-be-less-than 1.0)
        (expect (process-live-p proc) :not :to-be-truthy)
        (expect (plist-get error-data :stderr) :to-match "timed out")))))

(describe "mcumgr-task-cancel"
  (it "kills a running process"
    (mcumgr-tests--with-shell
      (let ((proc (mcumgr-run-async '("-c" "sleep 5"))))
        (expect (process-live-p proc) :to-be-truthy)
        (mcumgr-task-cancel proc)
        (sleep-for 0.1)
        (expect (process-live-p proc) :not :to-be-truthy))))

  (it "is a no-op on a process that has already exited"
    (mcumgr-tests--with-shell
      (let ((proc (mcumgr-run-async '("-c" "true"))))
        (mcumgr-tests--wait proc)
        (expect (mcumgr-task-cancel proc) :to-be-truthy)))))

;;; Logging

(describe "mcumgr--log"
  (before-each
    (when (get-buffer mcumgr-log-buffer-name)
      (kill-buffer mcumgr-log-buffer-name)))

  (it "appends a formatted entry on every sync invocation when enabled"
    (let ((mcumgr-log-enabled t))
      (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/echo")))
        (mcumgr--run "hello-from-sync"))
      (with-current-buffer mcumgr-log-buffer-name
        (let ((content (buffer-string)))
          (expect content :to-match "hello-from-sync")
          (expect content :to-match "exit=0")
          (expect content :to-match "elapsed=")))))

  (it "appends an entry for async invocations via the sentinel"
    (let ((mcumgr-log-enabled t))
      (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/sh")))
        (mcumgr-task-wait
          (mcumgr-run-async '("-c" "echo hello-from-async"))))
      (with-current-buffer mcumgr-log-buffer-name
        (expect (buffer-string) :to-match "hello-from-async"))))

  (it "records non-zero exits with the actual exit code"
    (let ((mcumgr-log-enabled t))
      (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/sh")))
        (condition-case _
          (mcumgr--run "-c" "echo nope >&2; exit 7")
          (mcumgr-exec-error nil)))
      (with-current-buffer mcumgr-log-buffer-name
        (let ((content (buffer-string)))
          (expect content :to-match "exit=7")
          (expect content :to-match "nope")
          (expect content :to-match "stderr:")))))

  (it "does not create the log buffer when disabled"
    (let ((mcumgr-log-enabled nil))
      (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/echo")))
        (mcumgr--run "x"))
      (expect (get-buffer mcumgr-log-buffer-name) :not :to-be-truthy))))

(describe "mcumgr-log-clear"
  (it "empties the log buffer in place"
    (let ((mcumgr-log-enabled t))
      (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/echo")))
        (mcumgr--run "foo"))
      (mcumgr-log-clear)
      (with-current-buffer mcumgr-log-buffer-name
        (expect (buffer-string) :to-equal ""))))

  (it "is a no-op when the log buffer does not exist"
    (when (get-buffer mcumgr-log-buffer-name)
      (kill-buffer mcumgr-log-buffer-name))
    (expect (mcumgr-log-clear) :not :to-throw)))

;;; Error hierarchy

(describe "mcumgr-error hierarchy"
  (it "treats specific errors as `mcumgr-error' subtypes"
    (expect (get 'mcumgr-exec-error      'error-conditions) :to-contain 'mcumgr-error)
    (expect (get 'mcumgr-transport-error 'error-conditions) :to-contain 'mcumgr-error)
    (expect (get 'mcumgr-parse-error     'error-conditions) :to-contain 'mcumgr-error))

  (it "treats `mcumgr-error' as a subtype of plain `error'"
    (expect (get 'mcumgr-error 'error-conditions) :to-contain 'error)))

;;; Transport

(describe "mcumgr--transport-args"
  (it "translates :udp to --udp ADDR"
    (expect (mcumgr--transport-args '(:udp "10.0.0.172"))
      :to-equal '("--udp" "10.0.0.172")))

  (it "translates :serial to --serial PATH"
    (expect (mcumgr--transport-args '(:serial "/dev/cu.usbmodem1101"))
      :to-equal '("--serial" "/dev/cu.usbmodem1101")))

  (it "translates :usb-serial to --usb-serial PATTERN"
    (expect (mcumgr--transport-args '(:usb-serial "303a:1001"))
      :to-equal '("--usb-serial" "303a:1001")))

  (it "signals an error for an empty transport plist"
    (expect (mcumgr--transport-args nil) :to-throw 'error)))

;;; Enumeration

(describe "mcumgr-usb-serial-devices"
  (it "parses the --json USB enumeration into a list of plists"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-usb-serial.json")
      (let* ((devices (mcumgr-usb-serial-devices))
              (first   (car devices)))
        (expect (length devices) :to-equal 2)
        (expect (plist-get first :identifier) :to-equal "303a:1001:1")
        (expect (plist-get first :port_name)  :to-equal "/dev/cu.usbmodem1101")
        (expect (plist-get (plist-get first :port_info) :vid)
          :to-equal 12346)
        (expect (plist-get (plist-get first :port_info) :manufacturer)
          :to-equal "Espressif"))))

  (it "passes --usb-serial --json to mcumgrctl"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-usb-serial-devices)
      (expect captured-args :to-equal '("--usb-serial" "--json")))))

(describe "mcumgr-serial-ports"
  (it "parses the --json serial enumeration into a list of strings"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-serial-ports.json")
      (expect (mcumgr-serial-ports)
        :to-equal '("/dev/cu.debug-console"
                     "/dev/tty.debug-console"
                     "/dev/cu.usbmodem1101"
                     "/dev/tty.usbmodem1101"))))

  (it "passes --serial --json to mcumgrctl"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-serial-ports)
      (expect captured-args :to-equal '("--serial" "--json")))))

;;; Connectivity

(describe "mcumgr-ping"
  (it "returns non-nil when the device responds"
    (mcumgr-tests--stub-run mcumgr-tests--ping-success-output
      (expect (mcumgr-ping '(:udp "10.0.0.172")) :to-be-truthy)))

  (it "returns nil when the output lacks the responsiveness marker"
    (mcumgr-tests--stub-run mcumgr-tests--ping-failure-output
      (expect (mcumgr-ping '(:udp "10.0.0.172")) :not :to-be-truthy)))

  (it "returns nil when `mcumgr--run' signals `mcumgr-exec-error'"
    (cl-letf (((symbol-function 'mcumgr--run)
                (lambda (&rest _) (signal 'mcumgr-exec-error
                                    '(:exit-code 1 :stderr "unreachable")))))
      (expect (mcumgr-ping '(:udp "10.0.0.172")) :not :to-be-truthy)))

  (it "translates the transport plist to the right flag"
    (mcumgr-tests--stub-run mcumgr-tests--ping-success-output
      (mcumgr-ping '(:serial "/dev/cu.usbmodem1101"))
      (expect captured-args :to-equal '("--serial" "/dev/cu.usbmodem1101")))))

;;; Image group

(describe "mcumgr-image-get-state"
  (it "parses the --json image state into a list of slot plists"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-image-get-state.json")
      (let* ((slots (mcumgr-image-get-state '(:udp "10.0.0.172")))
              (first (car slots)))
        (expect (length slots) :to-equal 1)
        (expect (plist-get first :image)     :to-equal 0)
        (expect (plist-get first :slot)      :to-equal 0)
        (expect (plist-get first :version)   :to-equal "0.0.0")
        (expect (plist-get first :bootable)  :to-be-truthy)
        (expect (plist-get first :confirmed) :to-be-truthy)
        (expect (plist-get first :pending)   :not :to-be-truthy))))

  (it "passes the transport + `image get-state --json' subcommand"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-image-get-state '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "image" "get-state" "--json")))))

(describe "mcumgr-image-slot-info"
  (it "parses the --json slot info into a list of image plists"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-image-slot-info.json")
      (let* ((images (mcumgr-image-slot-info '(:udp "10.0.0.172")))
              (first  (car images))
              (slots  (plist-get first :slots)))
        (expect (length images) :to-equal 1)
        (expect (plist-get first :image) :to-equal 0)
        (expect (length slots) :to-equal 2)
        (expect (plist-get (car slots) :slot) :to-equal 0)
        (expect (plist-get (car slots) :size) :to-equal 2949120))))

  (it "passes the transport + `image slot-info --json' subcommand"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-image-slot-info '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "image" "slot-info" "--json")))))

;;; OS group

(describe "mcumgr-os-task-statistics"
  (it "parses the --json task statistics into a hash-table keyed by task name"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-task-statistics.json")
      (let ((tasks (mcumgr-os-task-statistics '(:udp "10.0.0.172"))))
        (expect (hash-table-p tasks) :to-be-truthy)
        (let ((idle (gethash "idle" tasks)))
          (expect (gethash "prio" idle)  :to-equal 15)
          (expect (gethash "tid" idle)   :to-equal 15)
          (expect (gethash "state" idle) :to-equal 0))
        (let ((wifi (gethash "wifi" tasks)))
          (expect (gethash "prio" wifi)  :to-equal 5)
          (expect (gethash "state" wifi) :to-equal 128))
        (let ((smp (gethash "mcumgr smp" tasks)))
          (expect (gethash "tid" smp) :to-equal 1)))))

  (it "passes the transport + `os task-statistics --json' subcommand"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-os-task-statistics '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "os" "task-statistics" "--json")))))

(describe "mcumgr-os-mcumgr-parameters"
  (it "parses the --json MCUmgr parameters into a plist"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-mcumgr-parameters.json")
      (let ((params (mcumgr-os-mcumgr-parameters '(:udp "10.0.0.172"))))
        (expect (plist-get params :buf_count) :to-equal 2)
        (expect (plist-get params :buf_size)  :to-equal 2048))))

  (it "passes the transport + `os mcumgr-parameters --json' subcommand"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-os-mcumgr-parameters '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "os" "mcumgr-parameters" "--json")))))

(describe "mcumgr-os-application-info"
  (it "parses the --json application info into a hash-table"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-application-info.json")
      (let ((info (mcumgr-os-application-info '(:udp "10.0.0.172"))))
        (expect (hash-table-p info) :to-be-truthy)
        (expect (gethash "Kernel name" info)      :to-equal "Zephyr")
        (expect (gethash "Operating system" info) :to-equal "Zephyr")
        (expect (gethash "Machine" info)          :to-equal "xtensa"))))

  (it "passes the transport + `os application-info --json' subcommand"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-os-application-info '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "os" "application-info" "--json")))))

(describe "mcumgr-os-bootloader-info"
  (it "parses the --json bootloader info into a hash-table"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-bootloader-info.json")
      (let ((info (mcumgr-os-bootloader-info '(:udp "10.0.0.172"))))
        (expect (hash-table-p info) :to-be-truthy)
        (expect (gethash "Name" info)                :to-equal "MCUboot")
        (expect (gethash "Mode" info)                :to-equal 9)
        (expect (gethash "Downgrade Prevention" info) :not :to-be-truthy))))

  (it "passes the transport + `os bootloader-info --json' subcommand"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-os-bootloader-info '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "os" "bootloader-info" "--json")))))

;;; FS group

(describe "mcumgr-fs-status"
  (it "parses the --json file status into a plist with :length"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-fs-status.json")
      (let ((status (mcumgr-fs-status '(:udp "10.0.0.172") "/SD:/www/index.html")))
        (expect (plist-get status :length) :to-equal 1375))))

  (it "passes the transport + `fs status PATH --json' subcommand"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-fs-status '(:udp "10.0.0.172") "/SD:/www/index.html")
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "fs" "status" "/SD:/www/index.html" "--json")))))

(describe "mcumgr-fs-checksum"
  (it "parses the --json checksum into a hash-table with string keys"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-fs-checksum.json")
      (let ((result (mcumgr-fs-checksum '(:udp "10.0.0.172") "/SD:/www/index.html")))
        (expect (hash-table-p result) :to-be-truthy)
        (expect (gethash "checksum" result)    :to-equal "9a99f98b")
        (expect (gethash "type" result)        :to-equal "crc32")
        (expect (gethash "data length" result) :to-equal 1375)
        (expect (gethash "data offset" result) :to-equal 0))))

  (it "passes `fs checksum PATH --json' with no optional args"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-fs-checksum '(:udp "10.0.0.172") "/SD:/www/index.html")
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "fs" "checksum" "/SD:/www/index.html" "--json"))))

  (it "inserts ALGO before --json when given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-fs-checksum '(:udp "10.0.0.172") "/SD:/www/index.html" "crc32")
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "fs" "checksum" "/SD:/www/index.html" "crc32" "--json"))))

  (it "appends --offset and --length flags when given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-fs-checksum '(:udp "10.0.0.172") "/SD:/www/index.html" nil 64 512)
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "fs" "checksum" "/SD:/www/index.html"
                     "--offset" "64" "--length" "512" "--json")))))

;;; Stats group

(describe "mcumgr-stats-list-groups"
  (it "parses the --json group list into a list"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-stats-list-groups.json")
      (expect (mcumgr-stats-list-groups '(:udp "10.0.0.172")) :to-equal nil)))

  (it "passes the transport + `stats list-groups --json' subcommand"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-stats-list-groups '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "stats" "list-groups" "--json")))))

(describe "mcumgr-stats-get"
  (it "returns a hash-table when called without a group"
    (mcumgr-tests--stub-run "{}"
      (expect (hash-table-p (mcumgr-stats-get '(:udp "10.0.0.172"))) :to-be-truthy)))

  (it "passes the transport + `stats get --json' when no group given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-stats-get '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "stats" "get" "--json"))))

  (it "passes the group name before --json when given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-stats-get '(:udp "10.0.0.172") "net_stats")
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "stats" "get" "net_stats" "--json")))))

;;; Enum group

(describe "mcumgr-enum-list-groups"
  (it "parses the --json group list into a list of group IDs"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-enum-list-groups.json")
      (let ((groups (mcumgr-enum-list-groups '(:udp "10.0.0.172"))))
        (expect (length groups) :to-equal 8)
        (expect (car groups)  :to-equal 0)
        (expect (cadr groups) :to-equal 1)
        (expect (car (last groups)) :to-equal 63))))

  (it "passes the transport + `enum list-groups --json' subcommand"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-enum-list-groups '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "enum" "list-groups" "--json")))))

(describe "mcumgr-enum-show-group-details"
  (it "parses the --json group details into a list of plists"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-enum-show-group-details.json")
      (let* ((groups (mcumgr-enum-show-group-details '(:udp "10.0.0.172")))
              (os-mgmt (car groups))
              (zephyr  (car (last groups))))
        (expect (length groups) :to-equal 8)
        (expect (plist-get os-mgmt :group)    :to-equal 0)
        (expect (plist-get os-mgmt :name)     :to-equal "os mgmt")
        (expect (plist-get os-mgmt :handlers) :to-equal 9)
        (expect (plist-get zephyr :group)     :to-equal 63)
        (expect (plist-get zephyr :name)      :to-equal "zephyr basic mgmt"))))

  (it "passes the transport + `enum show-group-details --json' subcommand"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-enum-show-group-details '(:udp "10.0.0.172"))
      (expect captured-args
        :to-equal '("--udp" "10.0.0.172" "enum" "show-group-details" "--json")))))

;;; mcumgr-tests.el ends here
