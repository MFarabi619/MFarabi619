;;; process-compose-tests.el --- Buttercup tests for process-compose.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:  emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'process-compose)

(defconst process-compose-tests--fixtures-dir
  (expand-file-name "fixtures"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun process-compose-tests--fixture (file-name)
  "Return the contents of fixture FILE-NAME as a string."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name file-name process-compose-tests--fixtures-dir))
    (buffer-string)))

(defun process-compose-tests--parse (json-string)
  "Parse JSON-STRING into a list of state hashes."
  (append (json-parse-string json-string :false-object nil) nil))

(defun process-compose-tests--state (&rest properties)
  "Build a process state hash from keyword PROPERTIES."
  (let ((state (make-hash-table :test #'equal)))
    (puthash "name" "proc" state)
    (puthash "namespace" "default" state)
    (puthash "status" "Disabled" state)
    (puthash "is_ready" "-" state)
    (puthash "restarts" 0 state)
    (puthash "exit_code" 0 state)
    (puthash "mem" 0 state)
    (puthash "cpu" 0 state)
    (puthash "system_time" "-" state)
    (puthash "is_running" nil state)
    (cl-loop for (key value) on properties by #'cddr
             do (puthash (substring (symbol-name key) 1) value state))
    state))

(describe "process-compose--status-class"
  (it "mirrors getIconForState's status grouping"
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Disabled"))
            :to-be 'disabled)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Foreground"))
            :to-be 'disabled)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Pending"))
            :to-be 'pending)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Restarting"))
            :to-be 'restarting)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Terminating"))
            :to-be 'terminating)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Skipped"))
            :to-be 'skipped))
  (it "splits running states on the Not Ready health only"
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Running" :is_ready "Not Ready"))
            :to-be 'running-not-ready)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Running" :is_ready "Ready"))
            :to-be 'running)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Running" :is_ready "-"))
            :to-be 'running)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Launching"))
            :to-be 'running)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Running" :is_elevated t))
            :to-be 'running-elevated))
  (it "derives completed/failed from the success exit codes"
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Completed" :exit_code 0))
            :to-be 'completed)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Completed" :exit_code 1))
            :to-be 'failed)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Completed" :exit_code -1))
            :to-be 'failed)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Completed" :exit_code 3
                                           :success_exit_codes [3]))
            :to-be 'completed))
  (it "treats Error as failed and cron waits as scheduled"
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Error"))
            :to-be 'failed)
    (expect (process-compose--status-class
             (process-compose-tests--state :status "Completed" :exit_code 0
                                           :next_run_time "2026-07-03T00:00:00Z"))
            :to-be 'scheduled)))

(describe "process-compose--status-face"
  (it "maps each status class to a vui semantic face, per getIconForState"
    (expect (process-compose--status-face 'running)           :to-be 'vui-success)
    (expect (process-compose--status-face 'completed)         :to-be 'vui-success)
    (expect (process-compose--status-face 'running-not-ready) :to-be 'vui-warning)
    (expect (process-compose--status-face 'running-elevated)  :to-be 'vui-warning)
    (expect (process-compose--status-face 'skipped)           :to-be 'vui-warning)
    (expect (process-compose--status-face 'failed)            :to-be 'vui-error)
    (expect (process-compose--status-face 'pending)
            :to-be 'process-compose-pending)
    (expect (process-compose--status-face 'disabled)          :to-be 'vui-muted)
    (expect (process-compose--status-face 'scheduled)
            :to-be 'process-compose-scheduled)
    (expect (process-compose--status-face 'restarting)
            :to-be 'process-compose-attention)
    (expect (process-compose--status-face 'terminating)
            :to-be 'process-compose-terminating)))

(describe "process-compose--threshold-face"
  (it "keeps the row face below warning, escalating to attention then error"
    (expect (process-compose--threshold-face 30 '(50 . 85) 'row) :to-be 'row)
    (expect (process-compose--threshold-face 60 '(50 . 85) 'row)
            :to-be 'process-compose-attention)
    (expect (process-compose--threshold-face 90 '(50 . 85) 'row)
            :to-be 'vui-error)))

(describe "process-compose--display-process-status"
  (it "shows the raw status, with Failed for unsuccessful exits"
    (expect (process-compose--display-process-status
             (process-compose-tests--state :status "Running"))
            :to-equal "Running")
    (expect (process-compose--display-process-status
             (process-compose-tests--state :status "Completed" :exit_code 0))
            :to-equal "Completed")
    (expect (process-compose--display-process-status
             (process-compose-tests--state :status "Completed" :exit_code 1))
            :to-equal "Failed")
    (expect (process-compose--display-process-status
             (process-compose-tests--state :status "Completed" :exit_code -1))
            :to-equal "Failed"))
  (it "honours success_exit_codes"
    (expect (process-compose--display-process-status
             (process-compose-tests--state :status "Completed" :exit_code 3
                                           :success_exit_codes [3]))
            :to-equal "Completed"))
  (it "shows Scheduled for cron processes between runs"
    (expect (process-compose--display-process-status
             (process-compose-tests--state :status "Completed" :exit_code 0
                                           :next_run_time "2026-07-03T00:00:00Z"))
            :to-equal "Scheduled")))

(describe "process-compose--str-for-mem"
  (it "mirrors getStrForMem: byteCountIEC when running, dash otherwise"
    (expect (process-compose--str-for-mem 48234496 t) :to-equal "46.0 MiB")
    (expect (process-compose--str-for-mem 2031616 t) :to-equal "1.9 MiB")
    (expect (process-compose--str-for-mem (* 3 1024 1024 1024) t) :to-equal "3.0 GiB")
    (expect (process-compose--str-for-mem 0 t) :to-equal "-")
    (expect (process-compose--str-for-mem -1 t) :to-equal "unknown")
    (expect (process-compose--str-for-mem 48234496 nil) :to-equal "-")))

(describe "process-compose--str-for-cpu"
  (it "mirrors getStrForCPU: one decimal with percent when running"
    (expect (process-compose--str-for-cpu 14.5 t) :to-equal "14.5%")
    (expect (process-compose--str-for-cpu 0.0 t) :to-equal "0.0%")
    (expect (process-compose--str-for-cpu -1.0 t) :to-equal "unknown")
    (expect (process-compose--str-for-cpu 14.5 nil) :to-equal "-")))

(describe "process-compose--str-for-exit-code"
  (it "mirrors getStrForExitCode's three placeholder cases"
    (expect (process-compose--str-for-exit-code
             (process-compose-tests--state :status "Running" :is_running t
                                           :exit_code 0))
            :to-equal "-")
    (expect (process-compose--str-for-exit-code
             (process-compose-tests--state :status "Disabled"))
            :to-equal "-")
    (expect (process-compose--str-for-exit-code
             (process-compose-tests--state :status "Pending"))
            :to-equal "-")
    (expect (process-compose--str-for-exit-code
             (process-compose-tests--state :status "Completed" :exit_code 1))
            :to-equal "1")
    (expect (process-compose--str-for-exit-code
             (process-compose-tests--state :status "Completed" :exit_code -1))
            :to-equal "-1")
    (expect (process-compose--str-for-exit-code
             (process-compose-tests--state :status "Running" :is_running t
                                           :exit_code 2))
            :to-equal "2")))

(describe "process-compose--mode-line"
  (it "summarises running/total, aggregate memory and cpu like the TUI stats"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "a" :status "Running" :is_ready "Ready"
                  :is_running t :mem 1048576 :cpu 1.5)
                 (process-compose-tests--state :name "b" :status "Disabled"))))
      (let ((rendered (substring-no-properties (process-compose--mode-line))))
        (expect rendered :to-match "1/2")
        (expect rendered :to-match "1\\.0 MiB")
        (expect rendered :to-match "1\\.5"))))
  (it "escapes percent signs for the mode line"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "a" :status "Running" :is_running t :cpu 2.0))))
      (expect (substring-no-properties (process-compose--mode-line))
              :to-match "%%"))))

(describe "process-compose--icon"
  (it "renders a non-empty glyph across nerd-icon families"
    (expect (length (process-compose--icon "nf-md-check_bold" 'vui-success))
            :to-be-greater-than 0)
    (expect (length (process-compose--icon "nf-weather-train" 'vui-success))
            :to-be-greater-than 0)
    (expect (length (process-compose--icon "nf-seti-platformio" 'vui-success))
            :to-be-greater-than 0)))

(describe "process-compose-declare"
  (it "adds a new declaration"
    (let ((process-compose-processes nil))
      (process-compose-declare '(:name "web-serve" :namespace "web"
                                 :display-name "dx serve" :command "dx serve"))
      (expect (length process-compose-processes) :to-equal 1)))
  (it "replaces an existing declaration by name"
    (let ((process-compose-processes
           '((:name "web-serve" :namespace "web" :display-name "old"
              :command "old"))))
      (process-compose-declare '(:name "web-serve" :namespace "web"
                                 :display-name "dx serve" :command "new"))
      (expect (length process-compose-processes) :to-equal 1)
      (expect (plist-get (car process-compose-processes) :command)
              :to-equal "new"))))

(describe "process-compose-reconcile"
  (it "does nothing against an unreachable daemon"
    (spy-on 'process-compose--daemon-reachable-p :and-return-value nil)
    (spy-on 'process-compose--run-command)
    (process-compose-reconcile)
    (expect 'process-compose--run-command :not :to-have-been-called))
  (it "pushes a fresh config through project update when the daemon is up"
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/x.sock")
    (spy-on 'process-compose--daemon-reachable-p :and-return-value t)
    (spy-on 'process-compose--project-name :and-return-value "microvisor")
    (spy-on 'process-compose--write-config :and-return-value "/tmp/cfg.yaml")
    (spy-on 'process-compose--run-command)
    (process-compose-reconcile)
    (expect 'process-compose--run-command
            :to-have-been-called-with "project" "update" "-f" "/tmp/cfg.yaml"))
  (it "does nothing without a live daemon socket"
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/x.sock")
    (spy-on 'file-exists-p :and-return-value nil)
    (spy-on 'process-compose--run-command)
    (process-compose-reconcile)
    (expect 'process-compose--run-command :not :to-have-been-called)))

(describe "config emitter"
  (it "reads the legal config keys from the bundled upstream schema"
    (let ((keys (process-compose--config-keys)))
      (dolist (known-key '("working_dir" "ready_log_line" "shutdown"
                           "availability" "depends_on" "schedule"))
        (expect (member known-key keys) :to-be-truthy))
      (expect (member "bogus_key" keys) :to-be nil)))
  (it "rejects a typo'd config key at serialisation time, naming it"
    (let ((process-compose-processes
           '((:name "walter" :namespace "iot" :command "true"
              :config ((working_dri . "/tmp"))))))
      (expect (process-compose--project-config "p") :to-throw 'user-error)))
  (it "serialises the declarations into a loader-ready project"
    (let* ((process-compose-processes
            '((:name "pc-log" :namespace "debug" :display-name "pc log"
               :command "tail -F log" :config ((working_dir . "/tmp")))
              (:name "debug-fail" :namespace "debug" :display-name "fail"
               :command "exit 1" :disabled t)
              (:name "loco-start" :namespace "loco" :display-name "start"
               :command "cargo loco start" :disabled t
               :config ((readiness_probe
                         . ((http_get . ((host . "127.0.0.1")
                                         (port . 5150)
                                         (path . "/_health")))))))))
           (project (json-parse-string
                     (process-compose--project-config "microvisor")
                     :false-object nil)))
      (expect (gethash "version" project) :to-equal "0.5")
      (expect (gethash "name" project) :to-equal "microvisor")
      (expect (gethash "is_strict" project) :to-be t)
      (let ((processes (gethash "processes" project)))
        (expect (gethash "disabled" (gethash "debug-fail" processes)) :to-be t)
        (expect (gethash "disabled" (gethash "pc-log" processes)) :to-be nil)
        (expect (gethash "working_dir" (gethash "pc-log" processes))
                :to-equal "/tmp")
        (expect (gethash "command" (gethash "loco-start" processes))
                :to-equal "cargo loco start")
        (expect (gethash "port"
                         (gethash "http_get"
                                  (gethash "readiness_probe"
                                           (gethash "loco-start" processes))))
                :to-equal 5150))))
  (it "writes the project to a transient file the loader can read"
    (let* ((process-compose-processes
            '((:name "solo" :namespace "debug" :display-name "solo"
               :command "sleep 1" :disabled t)))
           (config-file (process-compose--write-config "test-project")))
      (unwind-protect
          (progn
            (expect (file-exists-p config-file) :to-be-truthy)
            (expect (string-suffix-p ".yaml" config-file) :to-be-truthy)
            (with-temp-buffer
              (insert-file-contents config-file)
              (expect (gethash "solo"
                               (gethash "processes"
                                        (json-parse-string (buffer-string))))
                      :to-be-truthy)))
        (delete-file config-file)))))

(describe "daemon log excerpt"
  (it "expands working_dir so the Go daemon can stat it"
    (let ((process-compose-processes
           '((:name "n" :namespace "x" :command "true"
              :config ((working_dir . "~/somewhere"))))))
      (expect (process-compose--project-config "p")
              :to-match (regexp-quote (expand-file-name "~/somewhere")))
      (expect (string-search "\"~/" (process-compose--project-config "p"))
              :to-be nil)))
  (it "collects the daemon-log lines mentioning a process"
    (let ((log-file (make-temp-file "pc-daemon-log")))
      (unwind-protect
          (progn
            (with-temp-file log-file
              (insert "INF something else\n"
                      "ERR Failed to run command for process ros2:simulator\n"
                      "INF more noise\n"))
            (spy-on 'process-compose--daemon-log-file
                    :and-return-value log-file)
            (expect (process-compose--daemon-log-excerpt "ros2:simulator")
                    :to-equal
                    '("ERR Failed to run command for process ros2:simulator")))
        (delete-file log-file))))
  (it "explains a never-started process inside its log pane"
    (spy-on 'process-compose--start-log-stream)
    (spy-on 'process-compose--daemon-log-excerpt
            :and-return-value '("ERR exec failed"))
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "walter" :status "Error"))))
      (let ((buffer (process-compose-log-buffer "walter")))
        (unwind-protect
            (with-current-buffer buffer
              (expect (buffer-string) :to-match "never started")
              (expect (buffer-string) :to-match "ERR exec failed"))
          (kill-buffer buffer))))))

(describe "state updates drive the dashboard"
  (it "publishing re-renders, reapplies the log pane, and runs the hook"
    (spy-on 'process-compose--rerender)
    (spy-on 'process-compose--follow-log-window)
    (let* ((hook-ran nil)
           (process-compose-after-update-hook
            (list (lambda () (setq hook-ran t)))))
      (with-current-buffer (get-buffer-create process-compose-buffer-name)
        (unwind-protect
            (progn
              (process-compose--publish-update)
              (expect 'process-compose--rerender :to-have-been-called)
              (expect 'process-compose--follow-log-window :to-have-been-called)
              (expect hook-ran :to-be-truthy))
          (kill-buffer process-compose-buffer-name))))))

(describe "metrics polling"
  (it "sees activity in running and transitional statuses only"
    (let ((process-compose--states
           (list (process-compose-tests--state :status "Completed"))))
      (expect (process-compose--any-process-active-p) :to-be nil))
    (let ((process-compose--states
           (list (process-compose-tests--state :status "Running"))))
      (expect (process-compose--any-process-active-p) :to-be-truthy))
    (let ((process-compose--states
           (list (process-compose-tests--state :is_running t))))
      (expect (process-compose--any-process-active-p) :to-be-truthy)))
  (it "polls process list only while the monitor lives and work is active"
    (spy-on 'make-process)
    (spy-on 'process-live-p :and-return-value nil)
    (process-compose--refresh-metrics)
    (expect 'make-process :not :to-have-been-called)
    (spy-on 'process-live-p :and-return-value t)
    (spy-on 'process-compose--any-process-active-p :and-return-value nil)
    (process-compose--refresh-metrics)
    (expect 'make-process :not :to-have-been-called)
    (spy-on 'process-compose--any-process-active-p :and-return-value t)
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/x.sock")
    (process-compose--refresh-metrics)
    (let ((command (plist-get (spy-calls-args-for 'make-process 0) :command)))
      (expect command :to-equal
              '("process-compose" "process" "list" "-o" "json"
                "--unix-socket" "/tmp/x.sock"))))
  (it "arms the poll timer alongside the monitor"
    (spy-on 'make-process :and-return-value 'fake-monitor)
    (spy-on 'run-with-timer :and-return-value 'fake-timer)
    (spy-on 'process-live-p :and-return-value nil)
    (let ((process-compose--monitor-process nil)
          (process-compose--metrics-timer nil))
      (process-compose--start-monitor)
      (expect 'run-with-timer :to-have-been-called-with
              process-compose-metrics-refresh-seconds
              process-compose-metrics-refresh-seconds
              #'process-compose--refresh-metrics)))
  (it "cancels the poll timer when the monitor dies"
    (spy-on 'cancel-timer)
    (spy-on 'process-compose--daemon-reachable-p :and-return-value nil)
    (let ((process-compose--metrics-timer 'fake-timer)
          (dead-process (start-process "pc-test-dead" nil "true")))
      (while (process-live-p dead-process)
        (accept-process-output nil 0.05))
      (process-compose--monitor-sentinel dead-process "died\n")
      (expect 'cancel-timer :to-have-been-called-with 'fake-timer))))

(describe "monitor stream fold"
  (it "upserts states from snapshot and live frames by process name"
    (let ((process-compose--states nil))
      (dolist (line (split-string
                     (process-compose-tests--fixture "monitor-stream.jsonl")
                     "\n" t))
        (process-compose--fold-monitor-line line))
      (expect (length process-compose--states) :to-equal 6)
      (expect (seq-count (lambda (state) (equal (gethash "name" state) "worker"))
                         process-compose--states)
              :to-equal 1)))
  (it "buffers partial chunks until a full line arrives"
    (let ((process-compose--states nil)
          (process-compose--monitor-fragment "")
          (line (car (split-string
                      (process-compose-tests--fixture "monitor-stream.jsonl")
                      "\n" t))))
      (process-compose--monitor-filter nil (substring line 0 20))
      (expect process-compose--states :to-be nil)
      (process-compose--monitor-filter nil (concat (substring line 20) "\n"))
      (expect (length process-compose--states) :to-equal 1)))
  (it "skips unparseable lines without losing the fold"
    (let ((process-compose--states nil))
      (process-compose--fold-monitor-line "not json at all")
      (expect process-compose--states :to-be nil)))
  (it "reconnects after an unexpected monitor exit while the daemon answers"
    (spy-on 'run-with-timer)
    (spy-on 'process-compose--daemon-reachable-p :and-return-value t)
    (let ((dead-process (start-process "pc-test-dead" nil "true")))
      (while (process-live-p dead-process) (accept-process-output nil 0.05))
      (process-compose--monitor-sentinel dead-process "exited abnormally\n")
      (expect 'run-with-timer :to-have-been-called)))
  (it "gives up when the daemon is unreachable"
    (spy-on 'run-with-timer)
    (spy-on 'process-compose--daemon-reachable-p :and-return-value nil)
    (let ((dead-process (start-process "pc-test-dead" nil "true")))
      (while (process-live-p dead-process) (accept-process-output nil 0.05))
      (process-compose--monitor-sentinel dead-process "exited abnormally\n")
      (expect 'run-with-timer :not :to-have-been-called)))
  (it "stays quiet when the exit was our own deliberate restart"
    (spy-on 'run-with-timer)
    (let ((dead-process (start-process "pc-test-dead" nil "true")))
      (while (process-live-p dead-process) (accept-process-output nil 0.05))
      (process-put dead-process 'process-compose-deliberate t)
      (process-compose--monitor-sentinel dead-process "killed\n")
      (expect 'run-with-timer :not :to-have-been-called))))

(describe "process-compose--state-at-point"
  (it "resolves the row's process name against the current states"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "walter"))))
      (with-temp-buffer
        (insert (propertize "row" 'process-compose-name "walter") "\n")
        (goto-char (point-min))
        (expect (gethash "name" (process-compose--state-at-point))
                :to-equal "walter"))))
  (it "returns nil on a line without the property"
    (with-temp-buffer
      (insert "plain\n")
      (goto-char (point-min))
      (expect (process-compose--state-at-point) :to-be nil))))

(describe "process-compose--sorted-states"
  (it "hides the hidden namespaces until toggled"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "tick" :namespace "debug")
                 (process-compose-tests--state :name "run" :namespace "tui")))
          (process-compose--show-hidden-namespaces nil))
      (expect (length (process-compose--sorted-states)) :to-equal 1)
      (let ((process-compose--show-hidden-namespaces t))
        (expect (length (process-compose--sorted-states)) :to-equal 2))))
  (it "orders rows by namespace, then name"
    (let ((process-compose--show-hidden-namespaces t)
          (process-compose--states
           (list (process-compose-tests--state :name "z" :namespace "web")
                 (process-compose-tests--state :name "b" :namespace "debug")
                 (process-compose-tests--state :name "a" :namespace "web")
                 (process-compose-tests--state :name "a" :namespace "debug"))))
      (expect (mapcar (lambda (state)
                        (cons (gethash "namespace" state)
                              (gethash "name" state)))
                      (process-compose--sorted-states))
              :to-equal '(("debug" . "a") ("debug" . "b")
                          ("web" . "a") ("web" . "z"))))))

(describe "process-compose-restart-failed"
  (it "starts exactly the processes whose last run failed"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "good" :status "Completed" :exit_code 0)
                 (process-compose-tests--state
                  :name "bad" :status "Completed" :exit_code 1)
                 (process-compose-tests--state
                  :name "broken" :status "Error" :exit_code 1)
                 (process-compose-tests--state :name "off"))))
      (spy-on 'process-compose--run-command)
      (process-compose-restart-failed)
      (expect 'process-compose--run-command
              :to-have-been-called-with "process" "start" "bad")
      (expect 'process-compose--run-command
              :to-have-been-called-with "process" "start" "broken")
      (expect (spy-calls-count 'process-compose--run-command) :to-equal 2)))
  (it "signals a user-error when nothing failed"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "off"))))
      (spy-on 'process-compose--run-command)
      (expect (process-compose-restart-failed) :to-throw 'user-error))))

(describe "process-compose-start-namespace"
  (it "delegates the bulk start to the daemon's namespace verb"
    (spy-on 'process-compose--run-command)
    (process-compose-start-namespace "firmware")
    (expect (spy-calls-args-for 'process-compose--run-command 0)
            :to-equal '("namespace" "start" "firmware"))
    (expect (spy-calls-count 'process-compose--run-command) :to-equal 1)))

(describe "process-compose--run-command"
  (it "invokes the executable against the session socket"
    (spy-on 'make-process)
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/test.sock")
    (process-compose--run-command "process" "start" "walter")
    (let ((command (plist-get (spy-calls-args-for 'make-process 0) :command)))
      (expect command :to-equal
              '("process-compose" "process" "start" "walter"
                "--unix-socket" "/tmp/test.sock")))))

(describe "actions"
  (it "start dispatches the CLI start for the process at point"
    (spy-on 'process-compose--row-name-at-point :and-return-value "walter")
    (spy-on 'process-compose--run-command)
    (process-compose-start-at-point)
    (expect 'process-compose--run-command
            :to-have-been-called-with "process" "start" "walter"))
  (it "stop dispatches the CLI stop"
    (spy-on 'process-compose--row-name-at-point :and-return-value "walter")
    (spy-on 'process-compose--run-command)
    (process-compose-stop-at-point)
    (expect 'process-compose--run-command
            :to-have-been-called-with "process" "stop" "walter"))
  (it "restart dispatches the CLI restart"
    (spy-on 'process-compose--row-name-at-point :and-return-value "walter")
    (spy-on 'process-compose--run-command)
    (process-compose-restart-at-point)
    (expect 'process-compose--run-command
            :to-have-been-called-with "process" "restart" "walter"))
  (it "signals a user-error on a line without a process"
    (spy-on 'process-compose--row-name-at-point :and-return-value nil)
    (expect (process-compose-start-at-point) :to-throw 'user-error)))

(describe "row navigation"
  (it "next/previous jump between process rows, skipping summary and headers"
    (let ((process-compose--states
           (process-compose-tests--parse
            (process-compose-tests--fixture "dashboard-mock.json"))))
      (unwind-protect
          (progn
            (vui-mount (vui-component 'process-compose-dashboard)
                       "*process-compose-nav-test*")
            (with-current-buffer "*process-compose-nav-test*"
              (goto-char (point-min))
              (process-compose-next-row)
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "ceratina-pio-run")
              (process-compose-next-row)
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "buttercup-test-all")
              (process-compose-previous-row)
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "ceratina-pio-run")))
        (when (get-buffer "*process-compose-nav-test*")
          (kill-buffer "*process-compose-nav-test*")))))
  (it "stays put at the edges"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "only"))))
      (unwind-protect
          (progn
            (vui-mount (vui-component 'process-compose-dashboard)
                       "*process-compose-nav-test*")
            (with-current-buffer "*process-compose-nav-test*"
              (goto-char (point-min))
              (process-compose-next-row)
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "only")
              (process-compose-next-row)
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "only")))
        (when (get-buffer "*process-compose-nav-test*")
          (kill-buffer "*process-compose-nav-test*")))))
  (it "enables full-row highlighting driven by the selected row's colour"
    (with-temp-buffer
      (process-compose-mode)
      (expect hl-line-mode :to-be-truthy)
      (expect (memq #'process-compose--react-to-selection post-command-hook)
              :to-be-truthy)))
  (it "tints the selection bar from the row at point"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "walter" :status "Running" :is_ready "Ready"))))
      (with-temp-buffer
        (process-compose-mode)
        (let ((inhibit-read-only t))
          (insert (propertize "walter" 'process-compose-name "walter") "\n"))
        (goto-char (point-min))
        (process-compose--update-selection-bar)
        (expect process-compose--selection-bar-cookie :to-be-truthy)
        (expect (assq 'hl-line face-remapping-alist) :to-be-truthy)))))

(describe "row face uniformity"
  (before-each
    (setq process-compose-visible-columns
          '("●" "PID" "NAME" "NAMESPACE" "STATUS" "AGE" "HEALTH"
            "MEM" "CPU" "RESTARTS" "EXIT CODE")))
  (after-each
    (setq process-compose-visible-columns
          (eval (car (get 'process-compose-visible-columns
                          'standard-value)))))
  (it "colours every cell of a row with its status face"
    (let* ((state (process-compose-tests--state
                   :name "walter" :status "Running" :is_ready "Ready"
                   :is_running t :pid 4242 :mem 1048576))
           (cells (process-compose--row state))
           (pid-cell (nth 1 cells)))
      (expect (vui-vnode-text-face pid-cell) :to-be 'vui-success)))
  (it "marks non-zero restart counts with the attention face"
    (let ((survivor (process-compose--row
                     (process-compose-tests--state
                      :name "a" :status "Running" :is_running t :restarts 2)))
          (clean (process-compose--row
                  (process-compose-tests--state
                   :name "b" :status "Running" :is_running t))))
      (expect (vui-vnode-text-face (nth 9 survivor))
              :to-be 'process-compose-attention)
      (expect (vui-vnode-text-face (nth 9 clean)) :to-be 'vui-success)))
  (it "tints hot cpu and mem cells past the thresholds"
    (let ((hot (process-compose--row
                (process-compose-tests--state
                 :name "a" :status "Running" :is_running t
                 :cpu 91.0 :mem (* 2 1024 1024 1024)))))
      (expect (vui-vnode-text-face (nth 8 hot)) :to-be 'vui-error)
      (expect (vui-vnode-text-face (nth 7 hot))
              :to-be 'process-compose-attention)))
  (it "keeps the name column bare of status icons"
    (let ((cells (process-compose--row
                  (process-compose-tests--state :name "walter" :status "Running"))))
      (expect (substring-no-properties (vui-vnode-text-content (nth 2 cells)))
              :to-equal "walter")))
  (it "displays the lisp-declared display name, keeping the full name as handle"
    (let ((process-compose-processes
           '((:name "web-serve" :namespace "web" :display-name "dx serve"
              :command "dx serve -p web"))))
      (let ((cells (process-compose--row
                    (process-compose-tests--state :name "web-serve" :namespace "web"))))
        (expect (substring-no-properties (vui-vnode-text-content (nth 2 cells)))
                :to-equal "dx serve")
        (expect (plist-get (vui-vnode-text-properties (nth 2 cells))
                           'process-compose-name)
                :to-equal "web-serve"))))
  (it "falls back to the raw name for undeclared processes"
    (let ((process-compose-processes nil))
      (let ((cells (process-compose--row
                    (process-compose-tests--state :name "some-foreign-process"))))
        (expect (substring-no-properties (vui-vnode-text-content (nth 2 cells)))
                :to-equal "some-foreign-process"))))
  (it "puts the status indicator in the gutter, per getIconForState"
    (let ((running (process-compose--row
                    (process-compose-tests--state :name "a" :status "Running")))
          (completed (process-compose--row
                      (process-compose-tests--state
                       :name "b" :status "Completed" :exit_code 0)))
          (failed (process-compose--row
                   (process-compose-tests--state
                    :name "c" :status "Completed" :exit_code 1)))
          (idle (process-compose--row
                 (process-compose-tests--state :name "d" :status "Disabled"))))
      (expect (vui-vnode-text-content (nth 0 running)) :to-equal "●")
      (expect (vui-vnode-text-content (nth 0 completed)) :to-equal "●")
      (expect (vui-vnode-text-content (nth 0 failed)) :to-equal "✘")
      (expect (vui-vnode-text-content (nth 0 idle)) :to-equal "◯")))
  (it "spins the gutter only for transitional statuses"
    (dolist (status '("Launching" "Launched" "Restarting" "Terminating"))
      (expect (seq-contains-p
               process-compose--spinner-frames
               (vui-vnode-text-content
                (nth 0 (process-compose--row
                        (process-compose-tests--state :name "a" :status status)))))
              :to-be-truthy))))

(describe "process-compose--namespace-cell"
  (it "wraps the namespace with its glyph on both sides"
    (let ((cell (process-compose--namespace-cell "loco" 'default)))
      (expect cell :to-match "loco")
      (expect (substring-no-properties cell 0 1)
              :to-equal (substring-no-properties cell -1))))
  (it "leaves unregistered namespaces bare"
    (expect (substring-no-properties
             (process-compose--namespace-cell "mystery" 'default))
            :to-equal "mystery")))

(describe "log pane"
  (it "creates a log buffer in log mode and starts its stream"
    (spy-on 'process-compose--start-log-stream)
    (let ((buffer (process-compose-log-buffer "walter")))
      (unwind-protect
          (with-current-buffer buffer
            (expect (derived-mode-p 'process-compose-log-mode) :to-be-truthy)
            (expect (buffer-name) :to-equal "*process-compose-log: walter*")
            (expect 'process-compose--start-log-stream
                    :to-have-been-called-with "walter" buffer))
        (kill-buffer buffer))))
  (it "requests the follow stream against the session socket"
    (spy-on 'make-process)
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/x.sock")
    (with-temp-buffer
      (process-compose--start-log-stream "walter" (current-buffer)))
    (let ((command (plist-get (spy-calls-args-for 'make-process 0) :command)))
      (expect command :to-equal
              '("process-compose" "process" "logs" "walter" "-f" "-n" "200"
                "--unix-socket" "/tmp/x.sock"))))
  (it "renders ansi chunks and keeps appending"
    (spy-on 'process-compose--start-log-stream)
    (let ((buffer (process-compose-log-buffer "walter")))
      (unwind-protect
          (progn
            (process-compose--log-insert
             buffer "\e[32mINF\e[0m walter listening\n")
            (process-compose--log-insert buffer "second line\n")
            (with-current-buffer buffer
              (expect (buffer-string)
                      :to-equal "INF walter listening\nsecond line\n")
              (expect (string-search "\e[" (buffer-string)) :to-be nil)))
        (kill-buffer buffer))))
  (it "reuses the buffer and does not start a second stream while one lives"
    (spy-on 'process-compose--start-log-stream
            :and-call-fake
            (lambda (_name buffer)
              (with-current-buffer buffer
                (setq process-compose-log--stream
                      (start-process "pc-test-stream" nil "sleep" "30")))))
    (let ((buffer (process-compose-log-buffer "walter")))
      (unwind-protect
          (progn
            (process-compose-log-buffer "walter")
            (expect (spy-calls-count 'process-compose--start-log-stream)
                    :to-equal 1))
        (with-current-buffer buffer
          (when (process-live-p process-compose-log--stream)
            (delete-process process-compose-log--stream)))
        (kill-buffer buffer))))
  (it "keeps the pane free of a header line"
    (spy-on 'process-compose--start-log-stream)
    (let ((buffer (process-compose-log-buffer "walter")))
      (unwind-protect
          (with-current-buffer buffer
            (expect header-line-format :to-be nil))
        (kill-buffer buffer))))
  (it "keeps split ansi escapes intact even across interleaved streams"
    (spy-on 'process-compose--start-log-stream)
    (let ((walter (process-compose-log-buffer "walter"))
          (bridge (process-compose-log-buffer "bridge")))
      (unwind-protect
          (progn
            (process-compose--log-insert walter "\e[3")
            (process-compose--log-insert bridge "\e[31mERR\e[0m other\n")
            (process-compose--log-insert walter "2mINF\e[0m split ok\n")
            (with-current-buffer walter
              (expect (buffer-string) :to-equal "INF split ok\n")
              (expect (string-search "\e[" (buffer-string)) :to-be nil))
            (with-current-buffer bridge
              (expect (buffer-string) :to-equal "ERR other\n")))
        (kill-buffer walter)
        (kill-buffer bridge))))
  (it "quit closes the log pane, stopping its stream, then the dashboard"
    (spy-on 'process-compose--log-window :and-return-value 'fake-window)
    (spy-on 'window-buffer :and-return-value 'fake-buffer)
    (spy-on 'process-compose--stop-log-stream)
    (spy-on 'delete-window)
    (spy-on 'quit-window)
    (process-compose-quit)
    (expect 'process-compose--stop-log-stream
            :to-have-been-called-with 'fake-buffer)
    (expect 'delete-window :to-have-been-called-with 'fake-window)
    (expect 'quit-window :to-have-been-called))
  (it "toggle opens the pane for a row with output and closes it when open"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "walter" :status "Running" :is_running t :pid 42)))
          (process-compose--log-pane-enabled-p nil))
      (spy-on 'process-compose--row-name-at-point :and-return-value "walter")
      (spy-on 'process-compose--log-window :and-return-value nil)
      (spy-on 'process-compose--display-log-window)
      (process-compose-logs-at-point)
      (expect 'process-compose--display-log-window :to-have-been-called)
      (kill-buffer "*process-compose-log: walter*")))
  (it "toggle on a quiet row enables following but keeps the pane closed"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "walter")))
          (process-compose--log-pane-enabled-p nil))
      (spy-on 'process-compose--row-name-at-point :and-return-value "walter")
      (spy-on 'process-compose--log-window :and-return-value nil)
      (spy-on 'process-compose--display-log-window)
      (process-compose-logs-at-point)
      (expect 'process-compose--display-log-window :not :to-have-been-called)
      (expect process-compose--log-pane-enabled-p :to-be-truthy))))

(describe "log pane follows signal"
  (it "judges worthiness by status: transition frames lack pid/is_running"
    (dolist (worthy-status '("Running" "Launching" "Restarting"
                             "Terminating" "Completed" "Error"))
      (expect (process-compose--log-worthy-p
               (process-compose-tests--state :status worthy-status))
              :to-be-truthy))
    (dolist (quiet-status '("Disabled" "Foreground" "Pending" "Skipped"))
      (expect (process-compose--log-worthy-p
               (process-compose-tests--state :status quiet-status))
              :to-be nil)))
  (it "closes the pane when the selection lands on a quiet row"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "walter")))
          (process-compose--log-pane-enabled-p t))
      (spy-on 'process-compose--state-at-point
              :and-return-value (car process-compose--states))
      (spy-on 'process-compose--close-log-window)
      (expect (process-compose--follow-log-window) :to-be nil)
      (expect 'process-compose--close-log-window :to-have-been-called)))
  (it "opens the pane when the selection reaches a worthy row"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "walter" :status "Running")))
          (process-compose--log-pane-enabled-p t))
      (spy-on 'process-compose--state-at-point
              :and-return-value (car process-compose--states))
      (spy-on 'process-compose--log-window :and-return-value nil)
      (spy-on 'process-compose--show-log-for)
      (expect (process-compose--follow-log-window) :to-be-truthy)
      (expect 'process-compose--show-log-for :to-have-been-called-with "walter")))
  (it "stays closed while following is disabled"
    (let ((process-compose--states
           (list (process-compose-tests--state
                  :name "walter" :status "Running")))
          (process-compose--log-pane-enabled-p nil))
      (spy-on 'process-compose--state-at-point
              :and-return-value (car process-compose--states))
      (spy-on 'process-compose--close-log-window)
      (spy-on 'process-compose--show-log-for)
      (expect (process-compose--follow-log-window) :to-be nil)
      (expect 'process-compose--show-log-for :not :to-have-been-called)))
  (it "leaves the pane alone when point is off the rows"
    (spy-on 'process-compose--state-at-point :and-return-value nil)
    (spy-on 'process-compose--close-log-window)
    (process-compose--follow-log-window)
    (expect 'process-compose--close-log-window :not :to-have-been-called)))

(describe "project guard"
  (it "refuses to manage a second project in one session"
    (spy-on 'process-compose--project-root :and-return-value "/other/repo/")
    (let ((process-compose--project (expand-file-name "/first/repo/")))
      (expect (process-compose-ensure) :to-throw 'user-error)))
  (it "passes through for the same project"
    (spy-on 'process-compose--project-root :and-return-value "/first/repo/")
    (spy-on 'process-compose--ensure-daemon)
    (spy-on 'process-compose--ensure-monitor)
    (let ((process-compose--project (expand-file-name "/first/repo/")))
      (process-compose-ensure)
      (expect 'process-compose--ensure-daemon :to-have-been-called))))

(describe "log stream lifecycle"
  (it "erases stale content before restarting a dead stream"
    (spy-on 'process-compose--start-log-stream)
    (let ((log-buffer (get-buffer-create "*process-compose-log: walter*")))
      (unwind-protect
          (progn
            (with-current-buffer log-buffer
              (process-compose-log-mode)
              (let ((inhibit-read-only t)) (insert "stale history\n")))
            (process-compose-log-buffer "walter")
            (with-current-buffer log-buffer
              (expect (buffer-string) :to-equal ""))
            (expect 'process-compose--start-log-stream :to-have-been-called))
        (kill-buffer log-buffer))))
  (it "stops a buffer's stream on demand"
    (let ((log-buffer (get-buffer-create "*process-compose-log: walter*")))
      (unwind-protect
          (progn
            (with-current-buffer log-buffer
              (process-compose-log-mode)
              (setq process-compose-log--stream
                    (start-process "pc-test-stream" nil "sleep" "30")))
            (process-compose--stop-log-stream log-buffer)
            (with-current-buffer log-buffer
              (expect (process-live-p process-compose-log--stream)
                      :to-be nil)))
        (kill-buffer log-buffer)))))

(describe "daemon reachability"
  (it "is nil without a socket file"
    (spy-on 'file-exists-p :and-return-value nil)
    (spy-on 'call-process)
    (expect (process-compose--daemon-reachable-p) :to-be nil)
    (expect 'call-process :not :to-have-been-called))
  (it "trusts our own live child without probing"
    (spy-on 'file-exists-p :and-return-value t)
    (spy-on 'process-live-p :and-return-value t)
    (spy-on 'call-process)
    (let ((process-compose--daemon-process 'child))
      (expect (process-compose--daemon-reachable-p) :to-be-truthy))
    (expect 'call-process :not :to-have-been-called))
  (it "probes a foreign socket and accepts an answering daemon"
    (spy-on 'file-exists-p :and-return-value t)
    (spy-on 'call-process :and-return-value 0)
    (let ((process-compose--daemon-process nil))
      (expect (process-compose--daemon-reachable-p) :to-be-truthy)))
  (it "rejects a stale socket whose daemon is gone"
    (spy-on 'file-exists-p :and-return-value t)
    (spy-on 'call-process :and-return-value 1)
    (let ((process-compose--daemon-process nil))
      (expect (process-compose--daemon-reachable-p) :to-be nil)))
  (it "ensure-daemon deletes a stale socket before spawning"
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/pc-test.sock")
    (spy-on 'process-compose--daemon-reachable-p :and-return-value nil)
    (spy-on 'file-exists-p :and-return-value t)
    (spy-on 'delete-file)
    (spy-on 'make-process)
    (spy-on 'process-compose--write-config :and-return-value "/tmp/pc-test.yaml")
    (spy-on 'process-compose--project-root :and-return-value "/tmp/")
    (spy-on 'process-compose--await-socket)
    (process-compose--ensure-daemon)
    (expect 'delete-file :to-have-been-called-with "/tmp/pc-test.sock")
    (expect 'make-process :to-have-been-called))
  (it "ensure-daemon leaves an answering daemon alone"
    (spy-on 'process-compose--socket-path :and-return-value "/tmp/pc-test.sock")
    (spy-on 'process-compose--daemon-reachable-p :and-return-value t)
    (spy-on 'make-process)
    (process-compose--ensure-daemon)
    (expect 'make-process :not :to-have-been-called)))

(describe "process-compose-down"
  (it "stops the whole project through the daemon"
    (spy-on 'process-compose--run-command)
    (process-compose-down)
    (expect (spy-calls-args-for 'process-compose--run-command 0)
            :to-equal '("down"))))

(describe "public seams"
  (it "process-compose-state resolves a live state by name"
    (let ((process-compose--states
           (list (process-compose-tests--state :name "walter"))))
      (expect (gethash "name" (process-compose-state "walter"))
              :to-equal "walter")
      (expect (process-compose-state "missing") :to-be nil)))
  (it "start/stop/restart-process drive the daemon by name"
    (spy-on 'process-compose--run-command)
    (process-compose-start-process "walter")
    (process-compose-stop-process "walter")
    (process-compose-restart-process "walter")
    (expect (spy-calls-args-for 'process-compose--run-command 0)
            :to-equal '("process" "start" "walter"))
    (expect (spy-calls-args-for 'process-compose--run-command 1)
            :to-equal '("process" "stop" "walter"))
    (expect (spy-calls-args-for 'process-compose--run-command 2)
            :to-equal '("process" "restart" "walter")))
  (it "monitor bursts run the after-update hook"
    (let* ((ran nil)
           (process-compose--states nil)
           (process-compose--monitor-fragment "")
           (process-compose-after-update-hook
            (list (lambda () (setq ran t)))))
      (process-compose--monitor-filter
       nil "{\"state\":{\"name\":\"walter\",\"status\":\"Running\"}}\n")
      (expect ran :to-be-truthy)
      (expect (gethash "name" (process-compose-state "walter"))
              :to-equal "walter"))))

(describe "process-compose-showcase"
  (it "loads one demonstration state per visual style"
    (let ((states (process-compose--showcase-states)))
      (expect (length states) :to-be-greater-than 12)
      (expect (seq-find (lambda (state) (equal (gethash "status" state) "Launching"))
                        states)
              :to-be-truthy)
      (expect (seq-find (lambda (state) (gethash "is_elevated" state)) states)
              :to-be-truthy)))
  (it "renders the showcase without a daemon"
    (spy-on 'process-compose--show-dashboard)
    (let ((process-compose--states nil)
          (process-compose--monitor-process nil))
      (process-compose-showcase)
      (expect (length process-compose--states) :to-be-greater-than 12)
      (expect 'process-compose--show-dashboard :to-have-been-called))))

(describe "process-compose entry point"
  (it "ensures the daemon and stream, keeping the pane closed on a quiet first row"
    (let ((process-compose--states
           (process-compose-tests--parse
            (process-compose-tests--fixture "dashboard-mock.json"))))
      (spy-on 'process-compose--ensure-daemon)
      (spy-on 'process-compose--start-monitor)
      (spy-on 'process-compose--display-log-window)
      (unwind-protect
          (progn
            (process-compose)
            (expect 'process-compose--ensure-daemon :to-have-been-called)
            (expect 'process-compose--start-monitor :to-have-been-called)
            (expect 'process-compose--display-log-window
                    :not :to-have-been-called)
            (with-current-buffer process-compose-buffer-name
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "ceratina-pio-run")))
        (dolist (buffer (buffer-list))
          (when (string-prefix-p "*process-compose" (buffer-name buffer))
            (kill-buffer buffer)))))))

(describe "column visibility"
  (it "renders only the configured columns, keeping NAME for row identity"
    (let ((process-compose-visible-columns '("●" "NAMESPACE"))
          (process-compose--states
           (list (process-compose-tests--state
                  :name "walter" :namespace "ros2"
                  :status "Running" :is_running t :pid 4242))))
      (unwind-protect
          (progn
            (vui-mount (vui-component 'process-compose-dashboard)
                       "*process-compose-test*")
            (with-current-buffer "*process-compose-test*"
              (let ((text (buffer-substring-no-properties (point-min)
                                                          (point-max))))
                (expect (string-search "walter" text) :to-be-truthy)
                (expect (string-search "ros2" text) :to-be-truthy)
                (expect (string-search "PID" text) :to-be nil)
                (expect (string-search "4242" text) :to-be nil)
                (expect (string-search "STATUS" text) :to-be nil)
                (expect (string-search "Running" text) :to-be nil))
              (goto-char (point-min))
              (process-compose-next-row)
              (expect (process-compose--row-name-at-point)
                      :to-equal "walter")))
        (kill-buffer "*process-compose-test*")))))

(describe "process-compose-dashboard rendering"
  (it "renders the TUI-style table: headers, every process, live columns"
    (let ((process-compose-visible-columns
           '("●" "PID" "NAME" "NAMESPACE" "STATUS" "AGE" "HEALTH"
             "MEM" "CPU" "RESTARTS" "EXIT CODE"))
          (process-compose-processes
           '((:name "web-serve" :namespace "web" :display-name "dx serve")
             (:name "loco-doctor" :namespace "loco" :display-name "doctor")))
          (process-compose--states
           (process-compose-tests--parse
            (process-compose-tests--fixture "dashboard-mock.json"))))
      (unwind-protect
          (progn
            (vui-mount (vui-component 'process-compose-dashboard)
                       "*process-compose-test*")
            (with-current-buffer "*process-compose-test*"
              (let ((text (buffer-substring-no-properties (point-min) (point-max))))
                (dolist (header '("PID" "NAME" "NAMESPACE" "STATUS" "AGE" "HEALTH"
                                  "MEM" "CPU" "RESTARTS" "EXIT CODE"))
                  (expect (string-search header text) :to-be-truthy))
                (expect (string-search "dx serve" text) :to-be-truthy)
                (expect (string-search "50681" text) :to-be-truthy)
                (expect (string-search "Disabled" text) :to-be-truthy)
                (expect (string-search "Failed" text) :to-be-truthy)
                (expect (string-search "46" text) :to-be-truthy))
              (goto-char (point-min))
              (search-forward "RESTARTS")
              (let ((header-face (get-text-property (match-beginning 0) 'face)))
                (expect (if (listp header-face)
                            (memq 'process-compose-table-header header-face)
                          (eq header-face 'process-compose-table-header))
                        :to-be-truthy))
              (goto-char (point-min))
              (search-forward "doctor")
              (expect (gethash "name" (process-compose--state-at-point))
                      :to-equal "loco-doctor")))
        (when (get-buffer "*process-compose-test*")
          (kill-buffer "*process-compose-test*"))))))

;;; process-compose-tests.el ends here
