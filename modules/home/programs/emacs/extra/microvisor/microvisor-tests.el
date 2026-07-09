;;; microvisor-tests.el --- Buttercup tests for microvisor.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'microvisor)

(defun microvisor-tests--task (&rest overrides)
  "Build a task plist from OVERRIDES over sane defaults."
  (append overrides '(:name "serve" :namespace "web" :command "trunk serve")))

(describe "microvisor-icon-face"
  (it "returns the registered face for a known tool"
    (expect (microvisor-icon-face "cargo") :to-equal 'nerd-icons-orange)
    (expect (microvisor-icon-face "west")  :to-equal 'nerd-icons-purple))
  (it "returns nil for an unknown tool"
    (expect (microvisor-icon-face "totally-fake") :not :to-be-truthy)))

(describe "microvisor--slug"
  (it "lowercases and hyphenates punctuation, trimming the edges"
    (expect (microvisor--slug "example:simulator(min)")
            :to-equal "example-simulator-min")
    (expect (microvisor--slug "build walter") :to-equal "build-walter")))

(describe "microvisor-task"
  (it "bakes the title, a tool+glyph annotation, and a daemon marker"
    (let* ((microvisor-namespace-icons '(("loco" . "L")))
           (microvisor-tool-display '(("cargo" "G" . nerd-icons-orange)))
           (task (microvisor-task
                  '(:name "start" :namespace "loco" :icon "R" :tool "cargo"
                    :command "cargo loco start" :runner daemon
                    :config ((availability . t))))))
      (expect (car task) :to-equal "L loco L:R start")
      (expect (plist-get (cdr task) :command) :to-equal "cargo loco start")
      (expect (plist-get (cdr task) :annotation) :to-equal "cargo G")
      (expect (plist-get (cdr task) :process-compose)
              :to-equal '((availability . t)))))
  (it "leaves a plain task unmarked, keeping the tool+glyph annotation"
    (let* ((microvisor-tool-display '(("cargo" "G" . nerd-icons-orange)))
           (task (microvisor-task
                  '(:name "db" :namespace "loco" :icon "D" :tool "cargo"
                    :command "cargo loco db"))))
      (expect (plist-member (cdr task) :process-compose) :to-be nil)
      (expect (plist-get (cdr task) :annotation) :to-equal "cargo G")))
  (it "falls back to a bare namespace label with no glyph or tool"
    (let ((microvisor-namespace-icons nil)
          (microvisor-tool-display nil))
      (expect (car (microvisor-task (microvisor-tests--task)))
              :to-equal "web:serve"))))

(describe "microvisor--process-compose-run"
  (before-each
    (spy-on 'process-compose-declare)
    (spy-on 'process-compose-ensure)
    (spy-on 'process-compose-reconcile)
    (spy-on 'process-compose-log-buffer)
    (spy-on 'display-buffer))
  (it "declares the task under its namespace, then starts it"
    (spy-on 'process-compose-state :and-return-value nil)
    (spy-on 'process-compose-start-process)
    (microvisor--process-compose-run "loco-serve" "loco" "trunk serve")
    (expect 'process-compose-declare :to-have-been-called-with
            '(:name "loco-serve" :namespace "loco" :command "trunk serve"))
    (expect 'process-compose-start-process
            :to-have-been-called-with "loco-serve"))
  (it "folds a config alist into the declaration"
    (spy-on 'process-compose-state :and-return-value nil)
    (spy-on 'process-compose-start-process)
    (microvisor--process-compose-run "loco-serve" "loco" "trunk serve"
                                     '((availability . t)))
    (expect 'process-compose-declare :to-have-been-called-with
            '(:name "loco-serve" :namespace "loco" :command "trunk serve"
              :config ((availability . t)))))
  (it "restarts a handle that already has board state"
    (spy-on 'process-compose-state :and-return-value (make-hash-table))
    (spy-on 'process-compose-restart-process)
    (microvisor--process-compose-run "loco-serve" "loco" "trunk serve")
    (expect 'process-compose-restart-process
            :to-have-been-called-with "loco-serve")))

(describe "board config (generated, not spied)"
  (it "serialises the declaration to valid JSON with a string namespace"
    (let ((process-compose-processes nil))
      (process-compose-declare
       (list :name "loco-serve" :namespace "loco" :command "trunk serve"
             :config '((availability . ((restart . "on_failure"))))))
      (let* ((parsed (json-parse-string (process-compose--project-config "t")))
             (proc (gethash "loco-serve" (gethash "processes" parsed))))
        (expect (gethash "namespace" proc) :to-equal "loco")
        (expect (gethash "command" proc) :to-equal "trunk serve")))))

(describe "microvisor--run-task"
  (before-each (spy-on 'compile))
  (it "routes a :process-compose task to the board, slugging the title"
    (spy-on 'compile-multi--get-task :and-return-value
            '("󰕮 microtop 󰕮: 󰳽 serve" :command "trunk serve" :process-compose t))
    (spy-on 'microvisor--process-compose-run)
    (microvisor--run-task)
    (expect 'microvisor--process-compose-run :to-have-been-called-with
            "microtop-serve" "microtop" "trunk serve" nil)
    (expect 'compile :not :to-have-been-called))
  (it "passes a :process-compose config alist through to the board"
    (spy-on 'compile-multi--get-task :and-return-value
            '("web: serve" :command "trunk serve"
              :process-compose ((availability . t))))
    (spy-on 'microvisor--process-compose-run)
    (microvisor--run-task)
    (expect 'microvisor--process-compose-run :to-have-been-called-with
            "web-serve" "web" "trunk serve" '((availability . t))))
  (it "compiles a plain string task"
    (spy-on 'compile-multi--get-task :and-return-value
            '("esp32s3: build" :command "cargo +esp bb"))
    (microvisor--run-task)
    (expect 'compile :to-have-been-called-with "cargo +esp bb"))
  (it "calls a function command directly"
    (spy-on 'compile-multi--get-task :and-return-value
            (list "west: patch" :command #'ignore))
    (spy-on 'ignore)
    (microvisor--run-task)
    (expect 'ignore :to-have-been-called)))

(describe "microvisor--compile-multi-annotation-advice"
  (it "tints a native :annotation with its named tool's face"
    (let ((result (microvisor--compile-multi-annotation-advice
                   (lambda (_) (copy-sequence "cargo +esp"))
                   '("t" :command "x" :annotation "cargo +esp "))))
      (expect (get-text-property 0 'face result) :to-be 'nerd-icons-orange)))
  (it "leaves an unknown-tool :annotation untinted"
    (expect (get-text-property
             0 'face (microvisor--compile-multi-annotation-advice
                      (lambda (_) (copy-sequence "whatever"))
                      '("t" :command "x" :annotation "notatool ")))
            :to-be nil))
  (it "returns the original untinted when there is no :annotation"
    (expect (microvisor--compile-multi-annotation-advice
             (lambda (_) "ORIG") '("t" :command "x"))
            :to-equal "ORIG")))

(describe "microvisor--group-margin-advice"
  (before-each (spy-on 'process-compose-state :and-return-value nil))
  (it "left-pads the stripped display and leaves the header alone"
    (expect (microvisor--group-margin-advice
             (lambda (_c _t) "build") "esp32s3:build" t)
            :to-equal " build")
    (expect (microvisor--group-margin-advice
             (lambda (_c _t) "esp32s3") "esp32s3:build" nil)
            :to-equal "esp32s3"))
  (it "tints a live process row by its status face"
    (spy-on 'microvisor--process-status :and-return-value '(vui-success . " "))
    (let ((row (microvisor--group-margin-advice
                (lambda (_c _t) "start") "loco:start" t)))
      (expect (substring-no-properties row) :to-equal " start")
      (expect (memq 'vui-success (ensure-list (get-text-property 0 'face row)))
              :to-be-truthy))))

(describe "microvisor--process-status"
  (it "maps a live process to its status face with a plain lead"
    (spy-on 'process-compose-state :and-return-value (make-hash-table :test 'equal))
    (spy-on 'process-compose--status-class :and-return-value 'failed)
    (let ((status (microvisor--process-status "loco:start")))
      (expect (car status) :to-be 'vui-error)
      (expect (cdr status) :to-equal " ")))
  (it "returns nil when the title has no live process"
    (spy-on 'process-compose-state :and-return-value nil)
    (expect (microvisor--process-status "esp32s3:build") :to-be nil)))

(describe "microvisor--picker-refresh"
  (it "installs then removes the timer and states hook"
    (microvisor--picker-refresh t)
    (expect microvisor--picker-timer :to-be-truthy)
    (expect (memq #'microvisor--refresh-picker
                  process-compose--states-updated-hook) :to-be-truthy)
    (microvisor--picker-refresh nil)
    (expect microvisor--picker-timer :to-be nil)
    (expect (memq #'microvisor--refresh-picker
                  process-compose--states-updated-hook) :to-be nil)))

(describe "process-compose end-to-end (real daemon, no spies)"
  (it "runs a :process-compose task and streams its output to the log"
    (assume (executable-find "process-compose") "process-compose not installed")
    (let* ((dir (make-temp-file "microvisor-e2e-" t))
           (default-directory (file-name-as-directory dir)))
      (call-process "git" nil nil nil "init")
      (unwind-protect
          (progn
            (microvisor--process-compose-run
             "e2e-echo" "test" "echo E2E_MARKER; sleep 2")
            (let ((deadline (+ (float-time) 15)))
              (while (and (< (float-time) deadline)
                          (not (string-match-p
                                "E2E_MARKER"
                                (with-current-buffer
                                    (process-compose-log-buffer "e2e-echo")
                                  (buffer-string)))))
                (accept-process-output nil 0.2)))
            (expect (with-current-buffer (process-compose-log-buffer "e2e-echo")
                      (buffer-string))
                    :to-match "E2E_MARKER"))
        (ignore-errors (process-compose-down))
        (dotimes (_ 10) (accept-process-output nil 0.2))
        (ignore-errors (delete-directory dir t))))))

(describe "load-time installation"
  (it "advises compile-multi's annotation and group functions"
    (expect (advice-member-p #'microvisor--compile-multi-annotation-advice
                             'compile-multi--annotation-function)
            :to-be-truthy)
    (expect (advice-member-p #'microvisor--group-margin-advice
                             'compile-multi--group-function)
            :to-be-truthy)))

;;; microvisor-tests.el ends here
