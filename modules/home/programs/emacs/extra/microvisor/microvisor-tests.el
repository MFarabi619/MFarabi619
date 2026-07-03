;;; microvisor-tests.el --- Buttercup tests for microvisor.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'microvisor)

(describe "microvisor-icon-face"
  (it "returns the registered face for a known prefix"
    (expect (microvisor-icon-face "cargo")  :to-equal 'nerd-icons-orange)
    (expect (microvisor-icon-face "west")   :to-equal 'nerd-icons-purple))

  (it "returns nil for an unknown prefix"
    (expect (microvisor-icon-face "totally-fake") :not :to-be-truthy)))

(describe "microvisor--split-title"
  (it "splits on the first colon and trims both halves"
    (expect (microvisor--split-title "ESP32S3 : test:hello")
            :to-equal '("ESP32S3" . "test:hello")))

  (it "returns the title in both halves when there is no colon"
    (expect (microvisor--split-title "activate")
            :to-equal '("activate" . "activate"))))

(describe "microvisor--annotation-function"
  (it "renders an icon in the registered face for a known prefix"
    (let* ((task   '("ESP32S3 : run" :annotation "     cargo X"))
           (result (microvisor--annotation-function
                    (lambda (_) "FALLBACK") task)))
      (expect (get-text-property (1- (length result)) 'face result)
              :to-equal 'nerd-icons-orange)))

  (it "falls back to ORIGINAL-FUNCTION when annotation lacks an icon glyph"
    (let* ((task   '("foo" :annotation "cargo"))
           (result (microvisor--annotation-function
                    (lambda (_) "FALLBACK") task)))
      (expect result :to-equal "FALLBACK")))

  (it "falls back to ORIGINAL-FUNCTION when there is no :annotation"
    (let ((result (microvisor--annotation-function
                   (lambda (_) "FALLBACK") '("foo"))))
      (expect result :to-equal "FALLBACK")))

  (it "falls back when the prefix is not in `microvisor-icon-faces'"
    (let* ((task   '("foo" :annotation "unknown-tool x"))
           (result (microvisor--annotation-function
                    (lambda (_) "FALLBACK") task)))
      (expect result :to-equal "FALLBACK")))

  (it "renders a lone glyph as an icon-only annotation, preserving its face"
    (let* ((glyph  (propertize "" 'face 'nerd-icons-yellow))
            (task   (list "foo" :annotation glyph))
            (result (microvisor--annotation-function (lambda (_) "FALLBACK") task)))
      (expect result :not :to-equal "FALLBACK")
      (expect result :to-match (regexp-quote ""))
      (expect (get-text-property (1- (length result)) 'face result)
              :to-equal 'nerd-icons-yellow)))

  (it "omits the label text by default, showing only the colored icon"
    (let* ((task   '("ESP32S3 : run" :annotation "cargo X"))
           (result (microvisor--annotation-function
                    (lambda (_) "FALLBACK") task)))
      (expect (substring-no-properties result) :not :to-match "cargo")
      (expect result :to-match "X")
      (expect (get-text-property (1- (length result)) 'face result)
              :to-equal 'nerd-icons-orange)))

  (it "shows the label text when `microvisor-annotation-show-label' is non-nil"
    (let* ((microvisor-annotation-show-label t)
           (task   '("ESP32S3 : run" :annotation "cargo X"))
           (result (microvisor--annotation-function
                    (lambda (_) "FALLBACK") task)))
      (expect (substring-no-properties result) :to-match "cargo"))))

(describe "microvisor--running-face-function"
  (it "greens the title of a running :process-compose task"
    (let ((process-compose--states
           (list (let ((state (make-hash-table :test #'equal)))
                   (puthash "name" "tui-run" state)
                   (puthash "is_running" t state)
                   state))))
      (let* ((task '(" tui  : run" :process-compose (:disabled t)))
             (result (car (microvisor--running-face-function
                           (lambda (tasks) tasks) (list task)))))
        (expect (memq 'success
                      (flatten-tree
                       (get-text-property 0 'face (car result))))
                :to-be-truthy))))
  (it "leaves stopped and unmarked tasks untouched"
    (let ((process-compose--states nil))
      (let* ((task '(" tui  : run" :process-compose (:disabled t)))
             (result (car (microvisor--running-face-function
                           (lambda (tasks) tasks) (list task)))))
        (expect (get-text-property 0 'face (car result)) :to-be nil))
      (let* ((task '("plain task" :command "x"))
             (result (car (microvisor--running-face-function
                           (lambda (tasks) tasks) (list task)))))
        (expect (car result) :to-equal "plain task")))))

(describe "microvisor--process-compose-slug"
  (it "slugifies a display name for the process handle"
    (expect (microvisor--process-compose-slug "run") :to-equal "run")
    (expect (microvisor--process-compose-slug "example:simulator(min)")
            :to-equal "example-simulator-min")
    (expect (microvisor--process-compose-slug "dx serve") :to-equal "dx-serve")))

(describe "microvisor--plain-label"
  (it "strips glyphs and whitespace"
    (expect (microvisor--plain-label "󰕮 microtop 󰕮") :to-equal "microtop")
    (expect (microvisor--plain-label " firmware ") :to-equal "firmware")
    (expect (microvisor--plain-label "󰍹 example:simulator")
            :to-equal "example:simulator")))

(describe "microvisor-register-process-compose-services"
  (before-each
    (spy-on 'process-compose-declare)
    (spy-on 'process-compose-reconcile)
    (spy-on 'projectile-project-root :and-return-value "/proj/"))

  (it "declares every :process-compose task, carrying flag-value extras"
    (let ((compile-multi-config nil))
      (microvisor-register-process-compose-services
       '((t ("󰕮 microtop 󰕮 :󰳽 serve" :command "trunk serve" :process-compose t)
            (" firmware  :󰍹 simulator" :command "cargo r" :process-compose (:disabled t))
            (" other  : plain" :command "x"))))
      (expect 'process-compose-declare :to-have-been-called-times 2)
      (let ((first-declaration (car (spy-calls-args-for 'process-compose-declare 0)))
            (second-declaration (car (spy-calls-args-for 'process-compose-declare 1))))
        (expect (plist-get first-declaration :name) :to-equal "microtop-serve")
        (expect (plist-get first-declaration :namespace) :to-equal "microtop")
        (expect (plist-get first-declaration :display-name) :to-equal "serve")
        (expect (plist-get first-declaration :command) :to-equal "trunk serve")
        (expect (plist-get second-declaration :name)
                :to-equal "firmware-simulator")
        (expect (plist-get second-declaration :display-name)
                :to-equal "simulator")
        (expect (plist-get second-declaration :disabled) :to-be t))
      (expect 'process-compose-reconcile :to-have-been-called))))

(describe "microvisor--maybe-register-services"
  (before-each (spy-on 'microvisor-register-process-compose-services))

  (it "no-ops when compile-multi-dir-local-config is unbound"
    (let (compile-multi-dir-local-config)
      (makunbound 'compile-multi-dir-local-config)
      (microvisor--maybe-register-services)
      (expect 'microvisor-register-process-compose-services
              :not :to-have-been-called)))

  (it "delegates when compile-multi-dir-local-config is bound and non-nil"
    (let ((compile-multi-dir-local-config
           '((t (" loco  : doctor" :command "x" :process-compose (:disabled t))))))
      (microvisor--maybe-register-services)
      (expect 'microvisor-register-process-compose-services
              :to-have-been-called))))

(describe "load-time installation"
  (it "registers `microvisor--annotation-function' as :around advice"
    (expect (advice-member-p #'microvisor--annotation-function
                             'compile-multi--annotation-function)
            :to-be-truthy))

  (it "registers `microvisor--running-face-function' as :around advice"
    (expect (advice-member-p #'microvisor--running-face-function
                             'compile-multi--add-properties)
            :to-be-truthy))

  (it "hooks `microvisor--maybe-register-services' into hack-local-variables-hook"
    (expect (memq #'microvisor--maybe-register-services
                  hack-local-variables-hook)
            :to-be-truthy)))

(describe "microvisor-sort-tasks"
  (it "places patch tasks right after update per the configured order"
    (expect
      (microvisor-sort-tasks
        '("W :* build aaa" "W :* patch apply" "W :* update" "W :* run aaa"))
      :to-equal
      '("W :* update" "W :* patch apply" "W :* run aaa" "W :* build aaa")))

  (it "orders by group, the configured command order, then target"
    (expect
      (microvisor-sort-tasks
        '("W :* flash bbb" "W :* build bbb" "W :* run aaa"
           "W :* build aaa" "W :* test aaa" "W :* update"))
      :to-equal
      '("W :* update" "W :* run aaa" "W :* test aaa"
         "W :* build aaa" "W :* build bbb" "W :* flash bbb")))

  (it "keeps tasks of different groups apart"
    (expect
      (microvisor-sort-tasks '("X :* build z" "W :* build a" "X :* build a"))
      :to-equal
      '("W :* build a" "X :* build a" "X :* build z")))

  (it "falls back to the raw candidate when it has no command form"
    (expect (microvisor-sort-tasks '("zeta" "alpha"))
      :to-equal '("alpha" "zeta")))

  (it "floats the most recent run's group and command to the top"
    (let ((compile-multi-history '("X :* build z")))
      (expect (microvisor-sort-tasks '("W :* run a" "X :* build a" "X :* build z"))
        :to-equal '("X :* build z" "X :* build a" "W :* run a"))))

  (it "registers a display-sort-function for the compile-multi category"
    (expect (alist-get 'display-sort-function
              (alist-get 'compile-multi completion-category-overrides))
      :to-equal #'microvisor-sort-tasks)))

;;; microvisor-tests.el ends here
