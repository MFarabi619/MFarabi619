;;; microvisor-tests.el --- Buttercup tests for microvisor.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'microvisor)

(describe "microvisor-icon-face"
  (it "returns the registered face for a known prefix"
    (expect (microvisor-icon-face "cargo")  :to-equal 'nerd-icons-orange)
    (expect (microvisor-icon-face "devenv") :to-equal 'nerd-icons-lblue)
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

(describe "microvisor--prodigy-running-face-function"
  :var (started?)
  (before-each
    (setq started? nil)
    (spy-on 'prodigy-find-service :and-return-value 'fake-service)
    (spy-on 'prodigy-service-started-p
            :and-call-fake (lambda (_) started?)))

  (it "adds prodigy-green-face to titles whose service is running"
    (setq started? t)
    (let* ((task   '("run" :prodigy t))
           (result (car (microvisor--prodigy-running-face-function
                         (lambda (tasks) tasks) (list task))))
           (title  (car result)))
      (expect (memq 'prodigy-green-face
                    (ensure-list (get-text-property 0 'face title)))
              :to-be-truthy)))

  (it "leaves the title unchanged when the service is not running"
    (let* ((task   '("run" :prodigy t))
           (result (car (microvisor--prodigy-running-face-function
                         (lambda (tasks) tasks) (list task)))))
      (expect (equal-including-properties result task) :to-be-truthy)))

  (it "ignores tasks without :prodigy"
    (let* ((task   '("run"))
           (result (car (microvisor--prodigy-running-face-function
                         (lambda (tasks) tasks) (list task)))))
      (expect (equal-including-properties result task) :to-be-truthy))))

(describe "microvisor-register-prodigy-services"
  (before-each
    (spy-on 'prodigy-define-service)
    (spy-on 'projectile-project-root :and-return-value "/proj/"))

  (it "defines one service per :prodigy task with name + command + cwd"
    (let ((compile-multi-config nil))
      (microvisor-register-prodigy-services
       '((t (" loco  : start"      :command "cargo loco start"     :prodigy t :port 5150)
            (" loco  : doctor"     :command "cargo loco doctor"    :prodigy t)
            (" ESP32  : run"       :command "cargo +esp rr"))))
      (expect 'prodigy-define-service :to-have-been-called-times 2)
      (let* ((first-args (spy-calls-args-for 'prodigy-define-service 0)))
        (expect (plist-get first-args :name)         :to-equal " loco  : start")
        (expect (plist-get first-args :group-label)  :to-equal "loco")
        (expect (plist-get first-args :display-name) :to-equal "start")
        (expect (plist-get first-args :cwd)          :to-equal "/proj/")
        (expect (plist-get first-args :port)         :to-equal 5150)
        (expect (plist-get first-args :command)      :to-equal shell-file-name)
        (expect (plist-get first-args :args)
                :to-equal (list shell-command-switch "cargo loco start")))))

  (it "omits :port when the task has none"
    (let ((compile-multi-config nil))
      (microvisor-register-prodigy-services
       '((t (" loco  : doctor" :command "cargo loco doctor" :prodigy t))))
      (let ((args (spy-calls-args-for 'prodigy-define-service 0)))
        (expect (plist-member args :port) :not :to-be-truthy)))))

(describe "microvisor--maybe-register-services"
  (before-each (spy-on 'microvisor-register-prodigy-services))

  (it "no-ops when compile-multi-dir-local-config is unbound"
    (let (compile-multi-dir-local-config)
      (makunbound 'compile-multi-dir-local-config)
      (microvisor--maybe-register-services)
      (expect 'microvisor-register-prodigy-services :not :to-have-been-called)))

  (it "delegates when compile-multi-dir-local-config is bound and non-nil"
    (let ((compile-multi-dir-local-config
           '((t (" loco  : doctor" :command "x" :prodigy t)))))
      (microvisor--maybe-register-services)
      (expect 'microvisor-register-prodigy-services :to-have-been-called))))

(describe "load-time installation"
  (it "registers `microvisor--annotation-function' as :around advice"
    (expect (advice-member-p #'microvisor--annotation-function
                             'compile-multi--annotation-function)
            :to-be-truthy))

  (it "registers `microvisor--prodigy-running-face-function' as :around advice"
    (expect (advice-member-p #'microvisor--prodigy-running-face-function
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

  (it "registers a display-sort-function for the compile-multi category"
    (expect (alist-get 'display-sort-function
              (alist-get 'compile-multi completion-category-overrides))
      :to-equal #'microvisor-sort-tasks)))

;;; microvisor-tests.el ends here
