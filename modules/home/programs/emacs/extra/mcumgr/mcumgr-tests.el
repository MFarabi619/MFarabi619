;;; mcumgr-tests.el --- Buttercup tests for mcumgr.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'mcumgr)

(defconst mcumgr-tests--usb-serial-json
  "[
  {
    \"identifier\": \"303a:1001:1\",
    \"port_name\": \"/dev/cu.usbmodem1101\",
    \"port_info\": {
      \"vid\": 12346,
      \"pid\": 4097,
      \"serial_number\": \"CC:BA:97:16:2B:68\",
      \"manufacturer\": \"Espressif\",
      \"product\": \"USB JTAG/serial debug unit\",
      \"interface\": 1
    }
  },
  {
    \"identifier\": \"303a:1001:1\",
    \"port_name\": \"/dev/tty.usbmodem1101\",
    \"port_info\": {
      \"vid\": 12346,
      \"pid\": 4097,
      \"serial_number\": \"CC:BA:97:16:2B:68\",
      \"manufacturer\": \"Espressif\",
      \"product\": \"USB JTAG/serial debug unit\",
      \"interface\": 1
    }
  }
]")

(defconst mcumgr-tests--serial-ports-json
  "[
  \"/dev/cu.debug-console\",
  \"/dev/tty.debug-console\",
  \"/dev/cu.usbmodem1101\",
  \"/dev/tty.usbmodem1101\"
]")

(defconst mcumgr-tests--ping-success-output
  "Device alive and responsive.\n")

(defconst mcumgr-tests--ping-failure-output
  "Error: connection timed out\n")

(defconst mcumgr-tests--image-state-json
  "[
  {
    \"image\": 0,
    \"slot\": 0,
    \"version\": \"0.0.0\",
    \"hash\": \"7af280662d5a726daeec0b644a93e69317f593f6be51b09f44244f5ab215a11e\",
    \"bootable\": true,
    \"pending\": false,
    \"confirmed\": true,
    \"active\": true,
    \"permanent\": false
  }
]")

(defmacro mcumgr-tests--stub-run (output &rest body)
  "Stub `mcumgr--run' to return OUTPUT and capture its args while BODY runs."
  (declare (indent 1))
  `(let (captured-args)
     (cl-letf (((symbol-function 'mcumgr--run)
                (lambda (&rest args) (setq captured-args args) ,output)))
       ,@body)))

(describe "mcumgr--run error handling"
  (it "raises `mcumgr-exec-error' on non-zero exit, carrying full context"
    (cl-letf (((symbol-function 'mcumgr--call)
               (lambda (_exe _args)
                 (list 1 "partial stdout" "Error: connection timed out\n"))))
      (condition-case err
          (progn (mcumgr--run "--udp" "10.0.0.1") (error "expected to signal"))
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
          (progn (mcumgr--run-json "--bogus") (error "expected to signal"))
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

(defmacro mcumgr-tests--with-shell (&rest body)
  "Override `mcumgr--executable' to /bin/sh while BODY runs.
Logging is disabled so the shared `*mcumgr*' buffer is not polluted."
  (declare (indent 0))
  `(let ((mcumgr-log-enabled nil))
     (cl-letf (((symbol-function 'mcumgr--executable) (lambda () "/bin/sh")))
       ,@body)))

(describe "mcumgr-run-async"
  (it "calls :on-exit with (exit-code stdout stderr) on termination"
    (mcumgr-tests--with-shell
      (let (result)
        (let ((proc (mcumgr-run-async
                     '("-c" "echo out; echo err >&2; exit 3")
                     :on-exit (lambda (code o e)
                                (setq result (list code o e))))))
          (while (process-live-p proc) (accept-process-output proc 0.05))
          (expect (nth 0 result) :to-equal 3)
          (expect (nth 1 result) :to-match "out")
          (expect (nth 2 result) :to-match "err")))))

  (it "calls :on-output for each complete stdout line"
    (mcumgr-tests--with-shell
      (let (lines)
        (let ((proc (mcumgr-run-async
                     '("-c" "echo a; echo b; echo c")
                     :on-output (lambda (line) (push line lines)))))
          (while (process-live-p proc) (accept-process-output proc 0.05))
          (expect (nreverse lines) :to-equal '("a" "b" "c"))))))

  (it "kills the underlying buffers when the process exits"
    (mcumgr-tests--with-shell
      (let* ((before (length (buffer-list)))
             (proc   (mcumgr-run-async '("-c" "echo done"))))
        (while (process-live-p proc) (accept-process-output proc 0.05))
        ;; Sentinel cleans up both stdout and stderr buffers.
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
            (progn (mcumgr-task-wait proc) (error "expected to signal"))
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
        (while (process-live-p proc) (accept-process-output proc 0.05))
        (expect (mcumgr-task-cancel proc) :to-be-truthy)))))

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

(describe "mcumgr-error hierarchy"
  (it "treats specific errors as `mcumgr-error' subtypes"
    (expect (get 'mcumgr-exec-error      'error-conditions) :to-contain 'mcumgr-error)
    (expect (get 'mcumgr-transport-error 'error-conditions) :to-contain 'mcumgr-error)
    (expect (get 'mcumgr-parse-error     'error-conditions) :to-contain 'mcumgr-error))

  (it "treats `mcumgr-error' as a subtype of plain `error'"
    (expect (get 'mcumgr-error 'error-conditions) :to-contain 'error)))

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

(describe "mcumgr-usb-serial-devices"
  (it "parses the --json USB enumeration into a list of plists"
    (mcumgr-tests--stub-run mcumgr-tests--usb-serial-json
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
    (mcumgr-tests--stub-run mcumgr-tests--serial-ports-json
      (expect (mcumgr-serial-ports)
              :to-equal '("/dev/cu.debug-console"
                          "/dev/tty.debug-console"
                          "/dev/cu.usbmodem1101"
                          "/dev/tty.usbmodem1101"))))

  (it "passes --serial --json to mcumgrctl"
    (mcumgr-tests--stub-run "[]"
      (mcumgr-serial-ports)
      (expect captured-args :to-equal '("--serial" "--json")))))

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

(describe "mcumgr-image-get-state"
  (it "parses the --json image state into a list of slot plists"
    (mcumgr-tests--stub-run mcumgr-tests--image-state-json
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

;;; mcumgr-tests.el ends here
