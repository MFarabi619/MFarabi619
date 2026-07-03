;;; mcumgr-tests.el --- Buttercup tests for mcumgr.el  -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Buttercup suite for mcumgr.el.  Fixture-first: every parser spec
;; runs against `fixtures/' captures of real `mcumgrctl' output, and
;; the manifest auto-generates parse-cleanly plus live-drift specs
;; (drift specs skip unless a device is reachable).  Panel components
;; mount headlessly with the runners spied to serve fixtures.
;;
;; Run:  eask test buttercup

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'mcumgr)
(require 'mcumgr-tramp)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)
(setq mcumgr-udp-address nil)

;;; Fixtures

(defconst mcumgr-tests--fixtures-dir
  (expand-file-name "fixtures/"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the captured `mcumgrctl' output fixtures.")

(defun mcumgr-tests--fixture (name)
  "Return the contents of `fixtures/NAME' as a string."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name mcumgr-tests--fixtures-dir))
    (buffer-string)))

(defun mcumgr-tests--fixture-json (name &optional object-type)
  "Parse `fixtures/NAME' as JSON with OBJECT-TYPE (default `plist')."
  (json-parse-string (mcumgr-tests--fixture name)
    :object-type (or object-type 'plist)
    :array-type 'list
    :false-object nil
    :null-object nil))

(defun mcumgr-tests--row-matches-p (row patterns)
  "Non-nil when each cell of ROW matches PATTERNS, nil entries skipped."
  (and (= (length row) (length patterns))
       (cl-every (lambda (cell pattern)
                   (or (null pattern) (string-match-p pattern cell)))
         row patterns)))

(buttercup-define-matcher-for-binary-function
    :to-match-row mcumgr-tests--row-matches-p)

(defconst mcumgr-tests--fixture-manifest
  '(("mcumgr-usb-serial.json"              "--usb-serial" "--json")
     ("mcumgr-serial-ports.json"            "--serial"     "--json")
     ("mcumgr-image-get-state.json"         "image" "get-state"         "--json")
     ("mcumgr-image-slot-info.json"         "image" "slot-info"         "--json")
     ("mcumgr-os-task-statistics.json"      "os" "task-statistics"      "--json")
     ("mcumgr-os-mcumgr-parameters.json"    "os" "mcumgr-parameters"    "--json")
     ("mcumgr-os-application-info.json"     "os" "application-info"     "--json")
     ("mcumgr-os-bootloader-info.json"      "os" "bootloader-info"      "--json")
     ("mcumgr-stats-list-groups.json"       "stats" "list-groups"       "--json")
     ("mcumgr-enum-list-groups.json"        "enum" "list-groups"        "--json")
     ("mcumgr-enum-show-group-details.json" "enum" "show-group-details" "--json")
     ("mcumgr-fs-status.json"               "fs" "status"   "/SD:/www/index.html" "--json")
     ("mcumgr-fs-checksum.json"             "fs" "checksum" "/SD:/www/index.html" "--json")
     ("mcumgr-shell-fs-ls-root.txt"    :text "shell" "fs" "ls" "/")
     ("mcumgr-shell-fs-ls-sd.txt"      :text "shell" "fs" "ls" "/SD:")
     ("mcumgr-shell-fs-ls-www.txt"     :text "shell" "fs" "ls" "/SD:/www")
     ("mcumgr-shell-fs-ls-public.txt"  :text "shell" "fs" "ls" "/SD:/www/public")
     ("mcumgr-shell-kernel-heap.txt"   :text "shell" "kernel" "heap")
     ("mcumgr-shell-kernel-uptime.txt" :text "shell" "kernel" "uptime")
     ("mcumgr-shell-device-list.txt"   :text "shell" "device" "list"))
  "Map each `fixtures/FILE' to the `mcumgrctl' args that produced it.")

(defcustom mcumgr-tests-transport nil
  "Transport plist enabling live drift specs; nil skips them."
  :type '(choice (const :tag "Skip" nil) sexp)
  :group 'mcumgr)

(defun mcumgr-tests--run-cli (&rest args)
  "Run `mcumgrctl ARGS', returning stdout as a string; error on non-zero exit."
  (with-temp-buffer
    (let ((exit-code (apply #'call-process "mcumgrctl" nil t nil args)))
      (unless (zerop exit-code)
        (error "Mcumgrctl %s failed (exit %d): %s"
          (string-join args " ") exit-code (buffer-string)))
      (buffer-string))))

;;; Inline fixtures

(defconst mcumgr-tests--ping-success-output "Device alive and responsive.\n")
(defconst mcumgr-tests--ping-failure-output "Error: connection timed out\n")

;;; Test helpers

(defmacro mcumgr-tests--stub-run (output &rest body)
  "Spy on `mcumgr--run', returning OUTPUT, while BODY runs."
  (declare (indent 1))
  `(progn
     (spy-on 'mcumgr--run :and-return-value ,output)
     ,@body))

(defmacro mcumgr-tests--with-shell (&rest body)
  "Spy `mcumgr--executable' to /bin/sh, quietly, for BODY on a reset queue."
  (declare (indent 0))
  `(progn
     (setq mcumgr--request-queue nil
       mcumgr--active-process nil)
     (spy-on 'mcumgr--executable :and-return-value "/bin/sh")
     (let ((mcumgr-log-enabled nil))
       ,@body)))

;;; Runner stub helpers

(defun mcumgr-tests--fixture-for-args (args)
  "Return the fixture file matching a mcumgrctl ARGS list."
  (cond ((member "application-info" args)   "mcumgr-os-application-info.json")
    ((member "bootloader-info" args)    "mcumgr-os-bootloader-info.json")
    ((member "mcumgr-parameters" args)  "mcumgr-os-mcumgr-parameters.json")
    ((member "show-group-details" args) "mcumgr-enum-show-group-details.json")
    ((member "slot-info" args)          "mcumgr-image-slot-info.json")
    ((member "get-state" args)          "mcumgr-image-get-state.json")
    ((member "get-image-info" args)     "mcumgr-firmware-get-image-info.json")
    ((member "task-statistics" args)    "mcumgr-os-task-statistics.json")
    ((and (member "kernel" args) (member "heap" args))
      "mcumgr-shell-kernel-heap.txt")
    ((and (member "kernel" args) (member "uptime" args))
      "mcumgr-shell-kernel-uptime.txt")
    ((and (member "device" args) (member "list" args))
      "mcumgr-shell-device-list.txt")
    ((and (member "fs" args) (member "ls" args))
      (cond ((member "/SD:/www/public" args) "mcumgr-shell-fs-ls-public.txt")
        ((member "/SD:/www" args) "mcumgr-shell-fs-ls-www.txt")
        ((member "/SD:" args)     "mcumgr-shell-fs-ls-sd.txt")
        (t                        "mcumgr-shell-fs-ls-root.txt")))
    ((equal args '("--serial" "--json")) "mcumgr-serial-ports.json")
    (t                                  "mcumgr-usb-serial.json")))

(defmacro mcumgr-tests--with-runner-stubs (&rest body)
  "Spy the runners to serve fixtures for BODY, on a reset queue."
  (declare (indent 0))
  `(progn
     (setq mcumgr--request-queue nil
       mcumgr--active-process nil)
     (spy-on 'mcumgr--run :and-call-fake
       (lambda (&rest args)
         (mcumgr-tests--fixture (mcumgr-tests--fixture-for-args args))))
     (spy-on 'mcumgr-run-async :and-call-fake
       (lambda (args &rest plist)
         (funcall (plist-get plist :on-exit) 0
           (mcumgr-tests--fixture (mcumgr-tests--fixture-for-args args))
           "")
         nil))
     ,@body))

(defun mcumgr-tests--mounted-content (component buffer-name regexp)
  "Mount COMPONENT in BUFFER-NAME; return content once REGEXP appears."
  (unwind-protect
    (progn
      (vui-mount (vui-component component) buffer-name)
      (with-current-buffer buffer-name
        (let ((deadline (+ (float-time) 2.0)))
          (while (and (not (string-match-p regexp (buffer-string)))
                   (< (float-time) deadline))
            (sit-for 0.05))
          (buffer-substring-no-properties (point-min) (point-max)))))
    (when (get-buffer buffer-name)
      (kill-buffer buffer-name))))

(defun mcumgr-tests--tasks (specs)
  "Build a task hash-table from SPECS of (NAME TID PRIO STATE RUNTIME)."
  (let ((tasks (make-hash-table :test #'equal)))
    (pcase-dolist (`(,name ,tid ,prio ,state ,runtime) specs)
      (let ((stats (make-hash-table :test #'equal)))
        (puthash "tid" tid stats)
        (puthash "prio" prio stats)
        (puthash "state" state stats)
        (puthash "runtime" runtime stats)
        (puthash name stats tasks)))
    tasks))

(defun mcumgr-tests--wait (process &optional done-p)
  "Pump events until PROCESS exits and DONE-P is non-nil."
  (with-timeout (5 (error "Mcumgr async wait timed out"))
    (while (or (process-live-p process) (and done-p (not (funcall done-p))))
      (accept-process-output nil 0.05))))

;;; Auto-generated fixture specs

(describe "every captured fixture"
  (dolist (entry mcumgr-tests--fixture-manifest)
    (let* ((name    (car entry))
            (text-p  (eq (cadr entry) :text))
            (args    (if text-p (cddr entry) (cdr entry)))
            (host-p  (member (car args) '("--usb-serial" "--serial")))
            (cli-command (format "mcumgrctl %s" (string-join args " "))))

      (it (format "stays in sync with `%s' on the running machine" cli-command)
        (assume (executable-find "mcumgrctl") "mcumgrctl not on PATH")
        (unless host-p
          (assume mcumgr-tests-transport
            "`mcumgr-tests-transport' unset (device transport required)"))
        (let* ((full-args (if host-p
                            args
                            (append (mcumgr--transport-args mcumgr-tests-transport) args)))
                (raw (apply #'mcumgr-tests--run-cli full-args)))
          (expect (length raw) :to-be-greater-than 0)
          (unless text-p
            (expect (json-parse-string raw) :not :to-throw)))))))

;;; Error handling

(describe "mcumgr--run error handling"
  (it "raises `mcumgr-exec-error' on non-zero exit, carrying full context"
    (mcumgr-tests--with-shell
      (let ((script "printf 'partial stdout'; echo 'Error: timed out' >&2; exit 1"))
        (condition-case err
          (progn (mcumgr--run "-c" script) (error "Expected to signal"))
          (mcumgr-exec-error
            (let ((error-data (cdr err)))
              (expect (plist-get error-data :exit-code) :to-equal 1)
              (expect (plist-get error-data :stdout)    :to-equal "partial stdout")
              (expect (plist-get error-data :stderr)    :to-match "timed out")
              (expect (plist-get error-data :args)      :to-equal (list "-c" script))))))))

  (it "returns stdout cleanly on zero exit"
    (mcumgr-tests--with-shell
      (expect (mcumgr--run "-c" "echo hello") :to-equal "hello\n"))))

(describe "request serialization"
  (it "runs one mcumgrctl process at a time, in FIFO order"
    (mcumgr-tests--with-shell
      (let (order first second third)
        (setq first  (mcumgr-run-async '("-c" "sleep 0.15; echo 1")
                       :on-exit (lambda (&rest _) (push 1 order))))
        (setq second (mcumgr-run-async '("-c" "echo 2")
                       :on-exit (lambda (&rest _) (push 2 order))))
        (setq third  (mcumgr-run-async '("-c" "echo 3")
                       :on-exit (lambda (&rest _) (push 3 order))))
        (expect (processp first) :to-be-truthy)
        (expect second :to-equal nil)
        (expect third  :to-equal nil)
        (expect (length mcumgr--request-queue) :to-equal 2)
        (mcumgr-tests--wait first (lambda () (equal (length order) 3)))
        (expect (nreverse order) :to-equal '(1 2 3))
        (expect mcumgr--request-queue :to-equal nil))))

  (it "lets a sync run wait its turn behind an async request"
    (mcumgr-tests--with-shell
      (let (order)
        (mcumgr-run-async '("-c" "sleep 0.1; echo async")
          :on-exit (lambda (&rest _) (push 'async order)))
        (push (cons 'sync (string-trim (mcumgr--run "-c" "echo sync"))) order)
        (expect (nreverse order) :to-equal '(async (sync . "sync"))))))

  (it "keeps a process dispatched from on-exit active through the cleanup"
    (mcumgr-tests--with-shell
      (let (follow-up first)
        (setq first
          (mcumgr-run-async '("-c" "true")
            :on-exit (lambda (&rest _)
                       (setq follow-up
                         (mcumgr-run-async '("-c" "sleep 0.3"))))))
        (mcumgr-tests--wait first (lambda () follow-up))
        (accept-process-output nil 0.05)
        (expect (process-live-p follow-up) :to-be-truthy)
        (expect mcumgr--active-process :to-equal follow-up)
        (mcumgr-process-cancel follow-up)
        (mcumgr-tests--wait follow-up))))

  (it "reports a spawn failure to its on-exit and keeps dispatching"
    (let ((spawn-count 0)
           first-exit failed-exit failed-stderr third-exit)
      (spy-on 'mcumgr--executable :and-call-fake
        (lambda ()
          (cl-incf spawn-count)
          (if (= spawn-count 2) "/nonexistent-mcumgrctl" "/bin/sh")))
      (let ((mcumgr-log-enabled nil))
        (let ((first (mcumgr-run-async '("-c" "sleep 0.1")
                       :on-exit (lambda (code &rest _)
                                  (setq first-exit code)))))
          (mcumgr-run-async '("-c" "true")
            :on-exit (lambda (code _stdout stderr)
                       (setq failed-exit code failed-stderr stderr)))
          (mcumgr-run-async '("-c" "true")
            :on-exit (lambda (code &rest _) (setq third-exit code)))
          (mcumgr-tests--wait first (lambda () third-exit))
          (expect first-exit :to-equal 0)
          (expect failed-exit :not :to-equal 0)
          (expect failed-stderr :to-match "nonexistent")
          (expect third-exit :to-equal 0)))))

  (it "dequeues a timed-out sync request and signals `mcumgr-exec-error'"
    (mcumgr-tests--with-shell
      (let ((mcumgr--run-timeout-seconds 0.2)
             (long (mcumgr-run-async '("-c" "sleep 3"))))
        (expect (mcumgr--run "-c" "true") :to-throw 'mcumgr-exec-error)
        (expect mcumgr--request-queue :to-equal nil)
        (mcumgr-process-cancel long)
        (mcumgr-tests--wait long)))))

(describe "mcumgr--run-json error handling"
  (it "raises `mcumgr-parse-error' when stdout is not valid JSON, carrying context"
    (spy-on 'mcumgr--run :and-return-value "this is not json")
    (let (debug-on-error)
      (condition-case err
        (progn (mcumgr--run-json "--bogus") (error "Expected to signal"))
        (mcumgr-parse-error
          (let ((error-data (cdr err)))
            (expect (plist-get error-data :output) :to-equal "this is not json")
            (expect (plist-get error-data :args)   :to-equal '("--bogus"))
            (expect (plist-get error-data :error)  :to-be-truthy))))))

  (it "propagates `mcumgr-exec-error' unchanged from the underlying `mcumgr--run'"
    (spy-on 'mcumgr--run :and-throw-error 'mcumgr-exec-error)
    (expect (mcumgr--run-json "x") :to-throw 'mcumgr-exec-error)))

;;; Async infrastructure

(describe "mcumgr-run-async"
  (it "calls :on-exit with (exit-code stdout stderr) on termination"
    (mcumgr-tests--with-shell
      (let (result)
        (let ((process (mcumgr-run-async
                      '("-c" "echo out; echo err >&2; exit 3")
                      :on-exit (lambda (exit-code stdout stderr)
                                 (setq result (list exit-code stdout stderr))))))
          (mcumgr-tests--wait process (lambda () result))
          (expect (nth 0 result) :to-equal 3)
          (expect (nth 1 result) :to-match "out")
          (expect (nth 2 result) :to-match "err")))))

  (it "calls :on-output for each complete stdout line"
    (mcumgr-tests--with-shell
      (let (lines)
        (let ((process (mcumgr-run-async
                      '("-c" "echo a; echo b; echo c")
                      :on-output (lambda (line) (push line lines)))))
          (mcumgr-tests--wait process (lambda () (= (length lines) 3)))
          (expect (nreverse lines) :to-equal '("a" "b" "c"))))))

  (it "kills the underlying buffers when the process exits"
    (mcumgr-tests--with-shell
      (let* ((before (length (buffer-list)))
              (process   (mcumgr-run-async '("-c" "echo done"))))
        (mcumgr-tests--wait process (lambda () (= (length (buffer-list)) before)))
        (expect (length (buffer-list)) :to-equal before)))))

(describe "mcumgr-process-wait"
  (it "blocks until exit and returns stdout"
    (mcumgr-tests--with-shell
      (expect (mcumgr-process-wait
                (mcumgr-run-async '("-c" "echo hello")))
        :to-equal "hello\n")))

  (it "signals `mcumgr-exec-error' on non-zero exit with full context"
    (mcumgr-tests--with-shell
      (let ((process (mcumgr-run-async
                    '("-c" "echo out; echo boom >&2; exit 5"))))
        (condition-case err
          (progn (mcumgr-process-wait process) (error "Expected to signal"))
          (mcumgr-exec-error
            (let ((error-data (cdr err)))
              (expect (plist-get error-data :exit-code) :to-equal 5)
              (expect (plist-get error-data :stderr)    :to-match "boom")))))))

  (it "kills the process and signals on timeout"
    (mcumgr-tests--with-shell
      (let* ((process  (mcumgr-run-async '("-c" "sleep 5")))
              (start (float-time))
              error-data)
        (condition-case err
          (mcumgr-process-wait process 0.15)
          (mcumgr-exec-error (setq error-data (cdr err))))
        (expect (- (float-time) start) :to-be-less-than 1.0)
        (expect (process-live-p process) :not :to-be-truthy)
        (expect (plist-get error-data :stderr) :to-match "timed out")))))

(describe "mcumgr-process-cancel"
  (it "kills a running process"
    (mcumgr-tests--with-shell
      (let ((process (mcumgr-run-async '("-c" "sleep 5"))))
        (expect (process-live-p process) :to-be-truthy)
        (mcumgr-process-cancel process)
        (sleep-for 0.1)
        (expect (process-live-p process) :not :to-be-truthy))))

  (it "returns nil without cancelling anything already exited or queued"
    (mcumgr-tests--with-shell
      (let ((process (mcumgr-run-async '("-c" "true"))))
        (mcumgr-tests--wait process)
        (expect (mcumgr-process-cancel process) :to-equal nil)
        (expect (mcumgr-process-cancel nil) :to-equal nil)))))

;;; Logging

(describe "mcumgr--log"
  (before-each
    (when (get-buffer mcumgr-log-buffer-name)
      (kill-buffer mcumgr-log-buffer-name)))

  (it "appends a formatted entry on every sync invocation when enabled"
    (let ((mcumgr-log-enabled t))
      (progn
        (spy-on 'mcumgr--executable :and-return-value "/bin/echo")
        (mcumgr--run "hello-from-sync"))
      (with-current-buffer mcumgr-log-buffer-name
        (let ((content (buffer-string)))
          (expect content :to-match "hello-from-sync")
          (expect content :to-match "exit=0")
          (expect content :to-match "elapsed=")))))

  (it "appends an entry for async invocations via the sentinel"
    (let ((mcumgr-log-enabled t))
      (progn
        (spy-on 'mcumgr--executable :and-return-value "/bin/sh")
        (mcumgr-process-wait
          (mcumgr-run-async '("-c" "echo hello-from-async"))))
      (with-current-buffer mcumgr-log-buffer-name
        (expect (buffer-string) :to-match "hello-from-async"))))

  (it "records non-zero exits with the actual exit code"
    (let ((mcumgr-log-enabled t))
      (progn
        (spy-on 'mcumgr--executable :and-return-value "/bin/sh")
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
      (progn
        (spy-on 'mcumgr--executable :and-return-value "/bin/echo")
        (mcumgr--run "x"))
      (expect (get-buffer mcumgr-log-buffer-name) :not :to-be-truthy))))

(describe "mcumgr-log-clear"
  (it "empties the log buffer in place"
    (let ((mcumgr-log-enabled t))
      (progn
        (spy-on 'mcumgr--executable :and-return-value "/bin/echo")
        (mcumgr--run "foo"))
      (mcumgr-log-clear)
      (with-current-buffer mcumgr-log-buffer-name
        (expect (buffer-string) :to-equal ""))))

  (it "is a no-op when the log buffer does not exist"
    (when (get-buffer mcumgr-log-buffer-name)
      (kill-buffer mcumgr-log-buffer-name))
    (expect (mcumgr-log-clear) :not :to-throw)))

;;; Error hierarchy

(describe "mcumgr--transport-args"
  (it "translates each transport kind to its backend flag"
    (expect (mcumgr--transport-args '(:udp "10.0.0.172"))
      :to-equal '("--udp" "10.0.0.172"))
    (expect (mcumgr--transport-args '(:serial "/dev/cu.usbmodem1101"))
      :to-equal '("--serial" "/dev/cu.usbmodem1101"))
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
          :to-equal "Espressif")))))

(describe "mcumgr-serial-ports"
  (it "parses the --json serial enumeration into a list of strings"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-serial-ports.json")
      (expect (mcumgr-serial-ports)
        :to-equal '("/dev/cu.debug-console"
                     "/dev/tty.debug-console"
                     "/dev/cu.usbmodem1101"
                     "/dev/tty.usbmodem1101")))))

;;; Connectivity

(describe "mcumgr-ping"
  (it "returns non-nil when the device responds"
    (mcumgr-tests--stub-run mcumgr-tests--ping-success-output
      (expect (mcumgr-ping '(:udp "10.0.0.172")) :to-be-truthy)))

  (it "returns nil when the output lacks the responsiveness marker"
    (mcumgr-tests--stub-run mcumgr-tests--ping-failure-output
      (expect (mcumgr-ping '(:udp "10.0.0.172")) :not :to-be-truthy)))

  (it "returns nil when `mcumgr--run' signals `mcumgr-exec-error'"
    (spy-on 'mcumgr--run :and-throw-error 'mcumgr-exec-error)
    (expect (mcumgr-ping '(:udp "10.0.0.172")) :not :to-be-truthy)))

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
        (expect (plist-get first :pending)   :not :to-be-truthy)))))

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
        (expect (plist-get (car slots) :size) :to-equal 2949120)))))

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
          (expect (gethash "tid" smp) :to-equal 1))))))

(describe "mcumgr-os-mcumgr-parameters"
  (it "parses the --json MCUmgr parameters into a plist"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-mcumgr-parameters.json")
      (let ((parameters (mcumgr-os-mcumgr-parameters '(:udp "10.0.0.172"))))
        (expect (plist-get parameters :buf_count) :to-equal 2)
        (expect (plist-get parameters :buf_size)  :to-equal 2048)))))

(describe "mcumgr-os-application-info"
  (it "parses the --json application info into a hash-table"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-application-info.json")
      (let ((info (mcumgr-os-application-info '(:udp "10.0.0.172"))))
        (expect (hash-table-p info) :to-be-truthy)
        (expect (gethash "Kernel name" info)      :to-equal "Zephyr")
        (expect (gethash "Operating system" info) :to-equal "Zephyr")
        (expect (gethash "Machine" info)          :to-equal "xtensa")))))

(describe "mcumgr-os-bootloader-info"
  (it "parses the --json bootloader info into a hash-table"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-os-bootloader-info.json")
      (let ((info (mcumgr-os-bootloader-info '(:udp "10.0.0.172"))))
        (expect (hash-table-p info) :to-be-truthy)
        (expect (gethash "Name" info)                :to-equal "MCUboot")
        (expect (gethash "Mode" info)                :to-equal 9)
        (expect (gethash "Downgrade Prevention" info) :not :to-be-truthy)))))

;;; FS group

(describe "mcumgr-fs-status"
  (it "parses the --json file status into a plist with :length"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-fs-status.json")
      (let ((status (mcumgr-fs-status '(:udp "10.0.0.172") "/SD:/www/index.html")))
        (expect (plist-get status :length) :to-equal 1375)))))

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
      (expect 'mcumgr--run :to-have-been-called-with "--udp" "10.0.0.172" "fs" "checksum" "/SD:/www/index.html" "--json")))

  (it "inserts ALGO before --json when given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-fs-checksum '(:udp "10.0.0.172") "/SD:/www/index.html" "crc32")
      (expect 'mcumgr--run :to-have-been-called-with "--udp" "10.0.0.172" "fs" "checksum" "/SD:/www/index.html" "crc32" "--json")))

  (it "appends --offset and --length flags when given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-fs-checksum '(:udp "10.0.0.172") "/SD:/www/index.html" nil 64 512)
      (expect 'mcumgr--run :to-have-been-called-with "--udp" "10.0.0.172" "fs" "checksum" "/SD:/www/index.html" "--offset" "64" "--length" "512" "--json"))))

;;; Stats group

(describe "mcumgr-stats-list-groups"
  (it "parses the --json group list into a list"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-stats-list-groups.json")
      (expect (mcumgr-stats-list-groups '(:udp "10.0.0.172")) :to-equal nil))))

(describe "mcumgr-stats-get"
  (it "returns a hash-table when called without a group"
    (mcumgr-tests--stub-run "{}"
      (expect (hash-table-p (mcumgr-stats-get '(:udp "10.0.0.172"))) :to-be-truthy)))

  (it "passes the transport + `stats get --json' when no group given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-stats-get '(:udp "10.0.0.172"))
      (expect 'mcumgr--run :to-have-been-called-with "--udp" "10.0.0.172" "stats" "get" "--json")))

  (it "passes the group name before --json when given"
    (mcumgr-tests--stub-run "{}"
      (mcumgr-stats-get '(:udp "10.0.0.172") "net_stats")
      (expect 'mcumgr--run :to-have-been-called-with "--udp" "10.0.0.172" "stats" "get" "net_stats" "--json"))))

;;; Enum group

(describe "mcumgr-enum-list-groups"
  (it "parses the --json group list into a list of group IDs"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-enum-list-groups.json")
      (let ((groups (mcumgr-enum-list-groups '(:udp "10.0.0.172"))))
        (expect (length groups) :to-equal 8)
        (expect (car groups)  :to-equal 0)
        (expect (cadr groups) :to-equal 1)
        (expect (car (last groups)) :to-equal 63)))))

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
        (expect (plist-get zephyr :name)      :to-equal "zephyr basic mgmt")))))

;;; Panel data shaping

(describe "mcumgr--thread-state-name"
  (it "decodes single, combined, and zero state bitfields"
    (expect (mcumgr--thread-state-name 0)   :to-equal "running")
    (expect (mcumgr--thread-state-name 2)   :to-equal "pending")
    (expect (mcumgr--thread-state-name 128) :to-equal "queued")
    (expect (mcumgr--thread-state-name 6)   :to-equal "pending+sleeping")))

(describe "mcumgr--thread-rows"
  (let ((tasks (mcumgr-tests--fixture-json "mcumgr-os-task-statistics.json" 'hash-table)))

    (it "excludes the idle baseline threads from the rows"
      (let ((rows (mcumgr--thread-rows tasks)))
        (expect (length rows) :to-equal 15)
        (expect (mapcar (lambda (row) (aref row 0)) rows)
          :not :to-contain "idle")))

    (it "excludes per-core idle threads on SMP devices"
      (let ((rows (mcumgr--thread-rows
                    (mcumgr-tests--tasks '(("idle 00" 15 15 0 1000)
                                            ("idle 01" 16 15 0 1000)
                                            ("wifi"    10  5 2  100))))))
        (expect (length rows) :to-equal 1)
        (expect (aref (car rows) 0) :to-equal "wifi")))

    (it "sorts by lifetime CPU% descending when no previous sample exists"
      (expect (car (mcumgr--thread-rows tasks))
        :to-match-row '("\\`wifi\\'" "\\`10\\'" "\\`5\\'" "\\`queued\\'" nil)))

    (it "computes lifetime CPU% against the total including idle"
      (let ((wifi-cpu (string-to-number
                        (aref (car (mcumgr--thread-rows tasks)) 4))))
        (expect wifi-cpu :to-be-greater-than 0.0)
        (expect wifi-cpu :to-be-less-than 5.0)))

    (it "computes delta CPU% between two samples"
      (let* ((previous (mcumgr-tests--tasks '(("idle" 15 15 0 1000)
                                               ("wifi" 10  5 2 1000))))
              (current  (mcumgr-tests--tasks '(("idle" 15 15 0 1100)
                                                ("wifi" 10  5 2 1300))))
              (rows     (mcumgr--thread-rows current previous)))
        (expect (length rows) :to-equal 1)
        (expect (aref (car rows) 0) :to-equal "wifi")
        (expect (aref (car rows) 4) :to-equal "75.0")))

    (it "treats threads absent from the previous sample as newly started"
      (let* ((previous (mcumgr-tests--tasks '(("idle" 15 15 0 1000))))
              (current  (mcumgr-tests--tasks '(("idle" 15 15 0 1100)
                                                ("new"   1  5 2  300))))
              (rows     (mcumgr--thread-rows current previous)))
        (expect (aref (car rows) 0) :to-equal "new")
        (expect (aref (car rows) 4) :to-equal "75.0")))))

(describe "mcumgr--thread-load"
  (it "sums the CPU% shares of the rows"
    (expect (mcumgr--thread-load (list ["a" "1" "5" "pending" "1.5"]
                                    ["b" "2" "5" "queued"  "0.2"]))
      :to-be-close-to 1.7 2)))

(describe "mcumgr--image-rows"
  (let ((slot-info (mcumgr-tests--fixture-json "mcumgr-image-slot-info.json"))
         (states    (mcumgr-tests--fixture-json "mcumgr-image-get-state.json")))

    (it "returns one row per slot, including stateless slots"
      (expect (length (mcumgr--image-rows slot-info states)) :to-equal 2))

    (it "merges slot state into the matching slot-info row"
      (let ((slot0 (car (mcumgr--image-rows slot-info states))))
        (expect slot0 :to-match-row
          '(" 0\\'" "\\`0\\.0\\.0\\'" "\\`2\\.8M\\'"
             "active confirmed bootable" "\\`7af28066\\'"))))

    (it "renders placeholders for slots without a flashed image"
      (expect (cadr (mcumgr--image-rows slot-info states))
        :to-match-row '(" 1\\'" "\\`—\\'" nil "\\`\\'" "\\`\\'")))

    (it "marks the active slot and the upload target with distinct glyphs"
      (let ((rows (mcumgr--image-rows slot-info states)))
        (expect (aref (car rows) 0)
          :not :to-equal (aref (cadr rows) 0))))))

(describe "mcumgr-udp-address"
  (it "is preferred by auto-select when set"
    (let ((mcumgr-udp-address "10.0.0.172")
           (mcumgr-transport nil))
      (expect (mcumgr--auto-select-transport)
        :to-equal '(:udp "10.0.0.172"))))

  (it "leaves explicit transports untouched at args level"
    (let ((mcumgr-udp-address "10.0.0.172"))
      (expect (mcumgr--transport-args '(:serial "/dev/cu.usbmodem1101"))
        :to-equal '("--serial" "/dev/cu.usbmodem1101"))))

  (it "falls back to USB auto-select when unset"
    (let ((mcumgr-udp-address nil)
           (mcumgr-transport nil))
      (mcumgr-tests--with-runner-stubs
        (expect (mcumgr--auto-select-transport)
          :to-equal '(:serial "/dev/cu.usbmodem1101"))))))

(describe "mcumgr--parse-kernel-heap"
  (it "parses free, allocated, and peak bytes from the shell output"
    (expect (mcumgr--parse-kernel-heap
              (mcumgr-tests--fixture "mcumgr-shell-kernel-heap.txt"))
      :to-equal '(:free 42052 :allocated 23308 :max-allocated 25036))))

(describe "mcumgr--system-lines"
  (it "drops the heap line when the shell reply is torn to a partial plist"
    (let ((lines (mcumgr--system-lines "free:  42052\nallocated" nil)))
      (expect lines :to-equal nil))))

(describe "mcumgr--parse-kernel-uptime"
  (it "parses the uptime milliseconds from the shell output"
    (expect (mcumgr--parse-kernel-uptime
              (mcumgr-tests--fixture "mcumgr-shell-kernel-uptime.txt"))
      :to-equal 10748011)))

(describe "mcumgr--format-uptime"
  (it "formats milliseconds as days, hours, and minutes"
    (expect (mcumgr--format-uptime 10748011) :to-equal "2h 59m")
    (expect (mcumgr--format-uptime 90061000) :to-equal "1d 1h 1m")
    (expect (mcumgr--format-uptime 65000)    :to-equal "1m")))

(describe "mcumgr--parse-driver-list"
  (let ((drivers (mcumgr--parse-driver-list
                   (mcumgr-tests--fixture "mcumgr-shell-device-list.txt"))))

    (it "parses every complete driver entry with state and labels"
      (expect (length drivers) :to-equal 7)
      (expect (car drivers)
        :to-equal '(:name "clock" :state "READY" :labels "clock"))
      (expect (nth 5 drivers)
        :to-equal '(:name "uart@60000000" :state "READY"
                     :labels "uart0 xiao_serial")))

    (it "skips lines torn by the SMP shell buffer limit"
      (expect (seq-find (lambda (driver)
                          (string-prefix-p "spi" (plist-get driver :name)))
                drivers)
        :to-equal nil))))

(describe "mcumgr--identity-lines"
  (let ((info (mcumgr-tests--fixture-json
                "mcumgr-os-application-info.json" 'hash-table))
         (bootloader (mcumgr-tests--fixture-json
                       "mcumgr-os-bootloader-info.json" 'hash-table))
         (parameters (mcumgr-tests--fixture-json
                       "mcumgr-os-mcumgr-parameters.json")))

    (it "orders the labelled identity values short to long"
      (expect (mapcar (lambda (line) (list (nth 2 line) (nth 3 line)))
                (mcumgr--identity-lines info bootloader parameters))
        :to-equal '(("arch" "xtensa")
                     ("node" "zephyr-1")
                     ("smp" "2 × 2048B")
                     ("bootloader" "MCUboot swap-offset")
                     ("platform" "xiao_esp32s3/esp32s3/procpu/sense")
                     ("kernel" "Zephyr v4.4.0-5566-ge79a0db70fc9"))))

    (it "drops lines whose query the device does not support"
      (expect (mapcar #'caddr (mcumgr--identity-lines info nil nil))
        :to-equal '("arch" "node" "platform" "kernel")))))

(describe "mcumgr--fetch-chain"
  (it "collects step results in order"
    (spy-on 'mcumgr-run-async :and-call-fake
      (lambda (args &rest plist)
        (funcall (plist-get plist :on-exit) 0
          (if (member "one" args) "[1]" "[2]") "")
        nil))
    (let (outcome)
      (mcumgr--fetch-chain
        (list (list :args '("one") :parse '(json plist list))
          (list :args '("two") :parse '(json plist list)))
        (lambda (results error-line) (setq outcome (list results error-line))))
      (expect outcome :to-equal '(((1) (2)) nil))))

  (it "aborts at the first required failure"
    (spy-on 'mcumgr-run-async :and-call-fake
      (lambda (_args &rest plist)
        (funcall (plist-get plist :on-exit) 1 "" "boom")
        nil))
    (let (outcome)
      (mcumgr--fetch-chain
        (list (list :args '("one") :parse '(json plist list))
          (list :args '("two") :parse '(json plist list)))
        (lambda (results error-line) (setq outcome (list results error-line))))
      (expect outcome :to-equal '(nil "boom"))
      (expect 'mcumgr-run-async :to-have-been-called-times 1)))

  (it "continues past optional failures with nil in that slot"
    (spy-on 'mcumgr-run-async :and-call-fake
      (lambda (args &rest plist)
        (if (member "two" args)
          (funcall (plist-get plist :on-exit) 1 "" "unsupported")
          (funcall (plist-get plist :on-exit) 0 "[1]" ""))
        nil))
    (let (outcome)
      (mcumgr--fetch-chain
        (list (list :args '("one") :parse '(json plist list))
          (list :args '("two") :parse '(json plist list)
            :optional t)
          (list :args '("three") :parse '(json plist list)))
        (lambda (results error-line) (setq outcome (list results error-line))))
      (expect outcome :to-equal '(((1) nil (1)) nil)))))

(describe "mcumgr-os-echo"
  (it "returns the device's echo response without the trailing newline"
    (mcumgr-tests--stub-run "ping-test\n"
      (expect (mcumgr-os-echo '(:serial "/dev/cu.usbmodem1101") "ping-test")
        :to-equal "ping-test"))))

(describe "mcumgr-fs-download"
  (it "returns the local destination path"
    (mcumgr-tests--stub-run ""
      (expect (mcumgr-fs-download '(:serial "/dev/cu.usbmodem1101")
                "/SD:/www/index.html" "/tmp/index.html")
        :to-equal "/tmp/index.html")))

  (it "round-trips a real file matching its fs-status length"
    (assume (executable-find "mcumgrctl") "mcumgrctl not on PATH")
    (assume mcumgr-tests-transport
      "`mcumgr-tests-transport' unset (device transport required)")
    (let ((download-file (make-temp-file "mcumgr-download-")))
      (unwind-protect
        (progn
          (mcumgr-fs-download mcumgr-tests-transport "/SD:/www/index.html"
            download-file)
          (expect (file-attribute-size (file-attributes download-file))
            :to-equal (plist-get
                        (mcumgr-tests--fixture-json "mcumgr-fs-status.json")
                        :length)))
        (delete-file download-file)))))

(describe "mcumgr-firmware-image-info"
  (it "parses the --json image info of a local MCUboot binary"
    (mcumgr-tests--stub-run (mcumgr-tests--fixture "mcumgr-firmware-get-image-info.json")
      (let ((info (mcumgr-firmware-image-info "/tmp/zephyr.signed.bin")))
        (expect (plist-get info :hash)
          :to-equal "084394b3101864e769d73c863f0baca69c0356c4dafd51d866b861b7916c8233")
        (expect (plist-get info :version) :to-equal "0.0.0")))))

(describe "mcumgr--build-row"
  (let ((info (mcumgr-tests--fixture-json "mcumgr-firmware-get-image-info.json"))
         (states (mcumgr-tests--fixture-json "mcumgr-image-get-state.json")))

    (it "reports a build absent from every slot as not flashed"
      (let ((row (mcumgr--build-row info 2949120 states)))
        (expect (aref row 0) :to-match "bin\\'")
        (expect (aref row 1) :to-equal "0.0.0")
        (expect (aref row 2) :to-equal "2.8M")
        (expect (aref row 3) :to-equal "not flashed")
        (expect (aref row 4) :to-equal "084394b3")))

    (it "reports the slot a matching build is flashed in"
      (let* ((flashed (list (plist-put (copy-sequence (car states))
                              :hash (plist-get info :hash))))
              (row (mcumgr--build-row info 2949120 flashed)))
        (expect (aref row 3) :to-equal "matches slot 0")))))

(describe "mcumgr--parse-fs-listing"
  (it "parses names, sizes, and directory markers from `fs ls' output"
    (expect (mcumgr--parse-fs-listing
              (mcumgr-tests--fixture "mcumgr-shell-fs-ls-sd.txt"))
      :to-equal '((:name "www" :size 0 :directory-p t)
                   (:name "sqlite.db" :size 0 :directory-p nil))))

  (it "parses file sizes from a populated directory"
    (let ((entries (mcumgr--parse-fs-listing
                     (mcumgr-tests--fixture "mcumgr-shell-fs-ls-www.txt"))))
      (expect (length entries) :to-equal 4)
      (expect (car entries)
        :to-equal '(:name "index.html" :size 1375 :directory-p nil))
      (expect (cadr entries)
        :to-equal '(:name "public" :size 0 :directory-p t))))

  (it "parses the mount roots"
    (expect (mcumgr--parse-fs-listing
              (mcumgr-tests--fixture "mcumgr-shell-fs-ls-root.txt"))
      :to-equal '((:name "SD:" :size 0 :directory-p t))))

  (it "drops a final line torn by the SMP shell buffer limit"
    (expect (mcumgr--parse-fs-listing "     12 whole.txt\r\n    345 torn")
      :to-equal '((:name "whole.txt" :size 12 :directory-p nil)))
    (expect (mcumgr--parse-fs-listing "     12 whole.txt\n    345 kept.db\n")
      :to-equal '((:name "whole.txt" :size 12 :directory-p nil)
                   (:name "kept.db" :size 345 :directory-p nil)))
    (expect (mcumgr--parse-fs-listing "garbage without size\n")
      :to-equal nil)))

(describe "mcumgr--tramp-file-name"
  (it "builds /mcumgr: names from the selected transport"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (expect (mcumgr--tramp-file-name "/SD:/www/index.html")
        :to-equal "/mcumgr:cu.usbmodem1101:/SD:/www/index.html"))
    (let ((mcumgr-transport '(:udp "10.0.0.172")))
      (expect (mcumgr--tramp-file-name "/SD:")
        :to-equal "/mcumgr:10.0.0.172:/SD:"))))

(describe "mcumgr--dired-setup"
  (it "marks device dired buffers attribute-safe for dirvish sizes"
    (assume (require 'dirvish nil t) "dirvish not available")
    (mcumgr-tests--with-runner-stubs
      (let ((buffer (dired-noselect (mcumgr--tramp-file-name "/"))))
        (unwind-protect
          (with-current-buffer buffer
            (expect (alist-get :sudo dirvish--props) :to-equal 1))
          (kill-buffer buffer)))))

  (it "hides details in device dired buffers"
    (mcumgr-tests--with-runner-stubs
      (let* ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101"))
              (buffer (dired-noselect (mcumgr--tramp-file-name "/"))))
        (unwind-protect
          (with-current-buffer buffer
            (expect dired-hide-details-mode :to-be-truthy)
            (expect (next-single-property-change (point-min) 'invisible)
              :to-be-truthy)
            (expect (buffer-string) :to-match "SD:"))
          (kill-buffer buffer))))))

(describe "mcumgr--auto-select-transport"
  (it "selects the device when exactly one is connected"
    (let ((mcumgr-transport nil))
      (mcumgr-tests--with-runner-stubs
        (expect (mcumgr--auto-select-transport)
          :to-equal '(:serial "/dev/cu.usbmodem1101")))))

  (it "selects nothing when no device is connected"
    (let ((mcumgr-transport nil))
      (spy-on 'mcumgr--run :and-return-value "[]")
      (expect (mcumgr--auto-select-transport) :to-equal nil)))

  (it "keeps an existing selection"
    (let ((mcumgr-transport '(:udp "10.0.0.172")))
      (mcumgr-tests--with-runner-stubs
        (expect (mcumgr--auto-select-transport)
          :to-equal '(:udp "10.0.0.172"))))))

(describe "mcumgr--threads-panel"
  (it "polls task statistics and renders the live table"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (mcumgr-tests--with-runner-stubs
        (let ((content (mcumgr-tests--mounted-content
                         'mcumgr--threads-panel "*mcumgr-test-threads*" "wifi")))
          (expect content :to-match "THREADS (15)")
          (expect content :to-match "CPU% · [0-9.]+%")
          (expect content :to-match "NAME")
          (expect content :not :to-match "idle")
          (expect content :to-match "wifi")))))

  (it "renders the device identity block below the table"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (mcumgr-tests--with-runner-stubs
        (let ((content (mcumgr-tests--mounted-content
                         'mcumgr--threads-panel "*mcumgr-test-threads*"
                         "wifi")))
          (expect content :to-match "uptime")
          (expect content :to-match "2h 59m")
          (expect content :to-match "heap")
          (expect content :to-match "23k used · 41k free · peak 24k")
          (expect content :to-match "xtensa")
          (expect content :to-match "zephyr-1")
          (expect content :to-match "2 × 2048B")
          (expect content :to-match "MCUboot swap-offset")
          (expect content :to-match "xiao_esp32s3/esp32s3/procpu/sense")
          (expect (string-match-p "NAME" content)
            :to-be-less-than (string-match-p "xtensa" content))))))

  (it "shows the transport error when the device is unreachable"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (spy-on 'mcumgr-run-async :and-call-fake
        (lambda (_args &rest plist)
          (funcall (plist-get plist :on-exit) 1 ""
            "Error: connection timed out")
          nil))
      (expect (mcumgr-tests--mounted-content
                'mcumgr--threads-panel "*mcumgr-test-threads*" "unreachable")
        :to-match "unreachable: Error: connection timed out"))))

(describe "mcumgr--images-panel"
  (it "renders one row per slot with merged state"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101"))
           (mcumgr-firmware-image-file nil))
      (mcumgr-tests--with-runner-stubs
        (let ((content (mcumgr-tests--mounted-content
                         'mcumgr--images-panel "*mcumgr-test-images*" "0\\.0\\.0")))
          (expect content :to-match "IMAGES (2)")
          (expect content :to-match "active confirmed bootable")
          (expect content :to-match "7af28066")))))

  (it "appends a build row comparing the local artifact to the slots"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101"))
           (mcumgr-firmware-image-file "/tmp/zephyr.signed.bin"))
      (spy-on 'file-exists-p :and-return-value t)
      (spy-on 'file-attributes :and-return-value nil)
      (mcumgr-tests--with-runner-stubs
        (let ((content (mcumgr-tests--mounted-content
                         'mcumgr--images-panel "*mcumgr-test-images*" "bin")))
          (expect content :to-match "not flashed")
          (expect content :to-match "084394b3"))))))

(describe "mcumgr--pio-device-locations"
  (it "maps ports to USB locations, skipping ports without one"
    (expect (mcumgr--pio-device-locations
              (mcumgr-tests--fixture "pio-device-list.json"))
      :to-equal '(("/dev/cu.usbmodem1101" . "1-1")))))

(describe "mcumgr--devices-panel"
  (it "renders the pio-style enumeration table with USB locations"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (mcumgr-tests--with-runner-stubs
        (spy-on 'mcumgr--fetch-pio-locations :and-call-fake
          (lambda (callback)
            (funcall callback '(("/dev/cu.usbmodem1101" . "1-1")))))
        (let ((content (mcumgr-tests--mounted-content
                         'mcumgr--devices-panel "*mcumgr-test-devices*"
                         "usbmodem")))
          (expect content :to-match "DEVICES (1)")
          (expect content :to-match "SERIAL")
          (expect content :to-match "VID:PID")
          (expect content :to-match "LOCATION")
          (expect content :to-match "/dev/cu\\.usbmodem1101")
          (expect content :to-match "AA:BB:CC:DD:EE:FF")
          (expect content :to-match "1-1")
          (expect content :to-match "USB JTAG/serial debug unit"))))))

(describe "mcumgr--drivers-panel"
  (it "renders an empty table rather than a spinner for an empty device list"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (spy-on 'mcumgr-run-async :and-call-fake
        (lambda (_args &rest plist)
          (funcall (plist-get plist :on-exit) 0 "devices:\n" "")
          nil))
      (let ((content (mcumgr-tests--mounted-content
                       'mcumgr--drivers-panel "*mcumgr-test-drivers*"
                       "DRIVERS")))
        (expect content :to-match "DRIVERS (0)")
        (expect content :not :to-match "fetching…")
        (expect content :to-match "NAME"))))

  (it "renders the driver table from the device list"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (mcumgr-tests--with-runner-stubs
        (let ((content (mcumgr-tests--mounted-content
                         'mcumgr--drivers-panel "*mcumgr-test-drivers*"
                         "gpio")))
          (expect content :to-match "DRIVERS (7)")
          (expect content :to-match "NAME")
          (expect content :to-match "DT LABELS")
          (expect content :to-match "gpio@60004800")
          (expect content :to-match "READY")
          (expect content :to-match "xiao_serial"))))))

(describe "mcumgr--dashboard panel"
  (it "stacks the devices, images, and threads sections in one buffer"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (mcumgr-tests--with-runner-stubs
        (spy-on 'mcumgr--fetch-pio-locations :and-call-fake
          (lambda (callback) (funcall callback nil)))
        (let ((content (mcumgr-tests--mounted-content
                        'mcumgr--dashboard "*mcumgr-dashboard-test*" "CPU%")))
          (expect content :to-match "DEVICES")
          (expect content :to-match "IMAGES")
          (expect content :to-match "THREADS")
          (expect (string-match-p "DEVICES" content)
            :to-be-less-than (string-match-p "IMAGES" content))
          (expect (string-match-p "IMAGES" content)
            :to-be-less-than (string-match-p "THREADS" content)))))))

(describe "mcumgr-mode"
  (it "derives from `vui-mode' and hides from M-x completion"
    (expect (get 'mcumgr-mode 'derived-mode-parent) :to-equal 'vui-mode)
    (expect (get 'mcumgr-mode 'completion-predicate) :to-equal #'ignore)))

(describe "mcumgr-quit"
  (it "kills the dashboard buffer but preserves the log"
    (let ((mcumgr-transport '(:serial "/dev/cu.usbmodem1101")))
      (mcumgr-tests--with-runner-stubs
        (with-current-buffer (get-buffer-create mcumgr-buffer-name)
          (unless (derived-mode-p 'mcumgr-mode) (mcumgr-mode)))
        (vui-mount (vui-component 'mcumgr--dashboard) mcumgr-buffer-name)
        (mcumgr--log-buffer)
        (mcumgr-quit)
        (expect (get-buffer mcumgr-buffer-name) :to-equal nil)
        (expect (get-buffer mcumgr-log-buffer-name) :to-be-truthy)))))

(describe "mcumgr--transport-label"
  (it "returns the address for each transport kind"
    (expect (mcumgr--transport-label '(:udp "10.0.0.172"))
      :to-equal "10.0.0.172")
    (expect (mcumgr--transport-label '(:serial "/dev/cu.usbmodem1101"))
      :to-equal "/dev/cu.usbmodem1101")))

;;; TRAMP method

(describe "mcumgr-tramp file names"
  (it "dissects hosts and colon-bearing localnames"
    (let ((vec (tramp-dissect-file-name "/mcumgr:usbmodem1101:/SD:/www")))
      (expect (tramp-file-name-method vec)    :to-equal "mcumgr")
      (expect (tramp-file-name-host vec)      :to-equal "usbmodem1101")
      (expect (tramp-file-name-localname vec) :to-equal "/SD:/www")))

  (it "prefers serial port matches over the UDP fallback"
    (mcumgr-tests--with-runner-stubs
      (expect (mcumgr-tramp--transport
                (tramp-dissect-file-name "/mcumgr:usbmodem1101:/"))
        :to-equal '(:serial "/dev/cu.usbmodem1101"))
      (expect (mcumgr-tramp--transport
                (tramp-dissect-file-name "/mcumgr:cu.usbmodem1101:/"))
        :to-equal '(:serial "/dev/cu.usbmodem1101"))
      (expect (mcumgr-tramp--transport
                (tramp-dissect-file-name "/mcumgr:10.0.0.172:/"))
        :to-equal '(:udp "10.0.0.172"))))

  (it "auto-picks the sole USB device on an empty host, ignoring non-USB ports"
    (mcumgr-tests--with-runner-stubs
      (spy-on 'mcumgr-serial-ports :and-return-value
        '("/dev/cu.usbmodem1101" "/dev/cu.PowerbeatsPro"
           "/dev/cu.Bluetooth-Incoming-Port"))
      (expect (mcumgr-tramp--transport (tramp-dissect-file-name "/mcumgr::/"))
        :to-equal '(:serial "/dev/cu.usbmodem1101"))))

  (it "resolves every host its own completion offers as serial"
    (mcumgr-tests--with-runner-stubs
      (let ((hosts (mapcar #'cadr (mcumgr-tramp-parse-device-names nil))))
        (expect hosts :not :to-equal nil)
        (dolist (host hosts)
          (expect (car (mcumgr-tramp--transport
                         (tramp-dissect-file-name
                           (format "/mcumgr:%s:/" host))))
            :to-equal :serial)))))

  (it "re-resolves on every call so one failure cannot poison the host"
    (mcumgr-tests--with-runner-stubs
      (let ((vec (tramp-dissect-file-name "/mcumgr:cu.usbmodem9999:/")))
        (spy-on 'mcumgr-usb-serial-devices :and-return-value nil)
        (expect (mcumgr-tramp--transport vec)
          :to-equal '(:udp "cu.usbmodem9999"))
        (spy-on 'mcumgr-usb-serial-devices :and-return-value
          '((:port_name "/dev/cu.usbmodem9999")))
        (expect (mcumgr-tramp--transport vec)
          :to-equal '(:serial "/dev/cu.usbmodem9999"))))))

(describe "mcumgr-tramp handlers"
  (before-each
    (tramp-cleanup-all-connections))
  (it "stats files and directories from one cached parent listing"
    (mcumgr-tests--with-runner-stubs
      (let ((attributes
              (file-attributes "/mcumgr:usbmodem1101:/SD:/www/index.html")))
        (expect (file-attribute-type attributes) :to-equal nil)
        (expect (file-attribute-size attributes) :to-equal 1375))
      (expect (file-directory-p "/mcumgr:usbmodem1101:/SD:/www")
        :to-be-truthy)
      (expect (length (seq-filter
                        (lambda (call) (member "/SD:/www" call))
                        (spy-calls-all-args 'mcumgr--run)))
        :to-equal 1)))

  (it "lists directories through dired's entry point"
    (mcumgr-tests--with-runner-stubs
      (expect (directory-files "/mcumgr:usbmodem1101:/SD:")
        :to-have-same-items-as '("." ".." "www" "sqlite.db"))))

  (it "completes file names with directory slashes"
    (mcumgr-tests--with-runner-stubs
      (expect (file-name-all-completions "tu" "/mcumgr:usbmodem1101:/SD:/www")
        :to-have-same-items-as '("tui.js" "tui_bg.wasm"))
      (expect (file-name-all-completions "pu" "/mcumgr:usbmodem1101:/SD:/www")
        :to-equal '("public/"))))

  (it "downloads through file-local-copy"
    (mcumgr-tests--with-runner-stubs
      (spy-on 'mcumgr-fs-download :and-call-fake
        (lambda (_transport _device-path local-path)
          (write-region "downloaded" nil local-path nil 'quiet)
          local-path))
      (let ((copy (file-local-copy "/mcumgr:usbmodem1101:/SD:/www/index.html")))
        (unwind-protect
          (progn
            (expect (spy-calls-args-for 'mcumgr-fs-download 0)
              :to-equal (list '(:serial "/dev/cu.usbmodem1101")
                          "/SD:/www/index.html" copy))
            (expect (with-temp-buffer
                      (insert-file-contents copy)
                      (buffer-string))
              :to-equal "downloaded"))
          (delete-file copy)))))

  (it "signals file-error on every mutating operation"
    (mcumgr-tests--with-runner-stubs
      (let (debug-on-error)
        (expect (write-region "x" nil "/mcumgr:usbmodem1101:/SD:/new.txt")
          :to-throw 'file-error)
        (expect (delete-file "/mcumgr:usbmodem1101:/SD:/sqlite.db")
          :to-throw 'file-error)
        (expect (make-directory "/mcumgr:usbmodem1101:/SD:/newdir")
          :to-throw 'file-error)))))

;;; mcumgr-tests.el ends here
