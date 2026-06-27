;;; pixi-tests.el --- Tests for pixi.el  -*- lexical-binding: t -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'pixi)

(defmacro pixi-tests--with-mocked-call (stdout exit &rest body)
  (declare (indent 2))
  `(let ((pixi-tests--captured-args nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (_program _infile _destination _display &rest args)
                  (setq pixi-tests--captured-args args)
                  (insert ,stdout)
                  ,exit)))
       ,@body)))

(defmacro pixi-tests--with-workspace (manifest-name manifest-body &rest body)
  (declare (indent 2))
  `(let* ((dir      (make-temp-file "pixi-test-" t))
          (manifest (expand-file-name ,manifest-name dir)))
     (unwind-protect
         (progn
           (with-temp-file manifest (insert ,manifest-body))
           (let ((default-directory (file-name-as-directory dir)))
             ,@body))
       (delete-directory dir t))))

(ert-deftest pixi-test-pyproject-with-tool-pixi ()
  (let ((tmp (make-temp-file "pyproject" nil ".toml")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "[project]\nname = \"x\"\n\n[tool.pixi.workspace]\nchannels = []\n"))
          (should (pixi--pyproject-has-pixi-p tmp)))
      (delete-file tmp))))

(ert-deftest pixi-test-pyproject-without-tool-pixi ()
  (let ((tmp (make-temp-file "pyproject" nil ".toml")))
    (unwind-protect
        (progn
          (with-temp-file tmp (insert "[project]\nname = \"x\"\n"))
          (should-not (pixi--pyproject-has-pixi-p tmp)))
      (delete-file tmp))))

(ert-deftest pixi-test-pyproject-missing-file ()
  (should-not (pixi--pyproject-has-pixi-p "/nonexistent/pyproject.toml")))

(ert-deftest pixi-test-detects-pixi-toml ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\nname = \"t\"\n"
    (should (pixi-p))
    (should (equal (pixi-manifest-file) manifest))))

(ert-deftest pixi-test-detects-pyproject-with-tool-pixi ()
  (pixi-tests--with-workspace
      "pyproject.toml" "[project]\nname=\"x\"\n[tool.pixi.workspace]\nchannels=[]\n"
    (should (pixi-p))
    (should (equal (pixi-manifest-file) manifest))))

(ert-deftest pixi-test-ignores-plain-pyproject ()
  (pixi-tests--with-workspace "pyproject.toml" "[project]\nname=\"x\"\n"
    (should-not (pixi-p))
    (should-not (pixi-manifest-file))))

(ert-deftest pixi-test-root-locates-dominating ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let* ((sub (expand-file-name "deep/nested/dir/" dir))
           (default-directory (progn (make-directory sub t) sub)))
      (should (equal (file-name-as-directory (expand-file-name (pixi-root)))
                     (file-name-as-directory (expand-file-name dir)))))))

(ert-deftest pixi-test-manifest-args-injects-path ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (should (equal (pixi--manifest-args)
                   (list "--manifest-path" manifest)))))

(ert-deftest pixi-test-call-appends-manifest-after-subcommand ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call "ok\n" 0
      (pixi--call '("info" "--json"))
      (should (equal pixi-tests--captured-args
                     (list "info" "--json" "--manifest-path" manifest))))))

(ert-deftest pixi-test-call-signals-on-nonzero-exit ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call "boom\n" 2
      (let ((err (should-error (pixi--call '("info")) :type 'error)))
        (should (string-match-p "exit 2" (cadr err)))
        (should (string-match-p "boom" (cadr err)))))))

(ert-deftest pixi-test-json-call-parses-as-alist ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call "{\"name\":\"x\",\"version\":\"1.0\"}" 0
      (let ((parsed (pixi--json-call '("info" "--json"))))
        (should (equal (alist-get 'name    parsed) "x"))
        (should (equal (alist-get 'version parsed) "1.0"))))))

(ert-deftest pixi-test-info-caches-by-mtime ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((calls 0))
      (cl-letf (((symbol-function 'call-process)
                 (lambda (&rest _)
                   (setq calls (1+ calls))
                   (insert "{\"version\":\"1.0\"}")
                   0)))
        (clrhash pixi--info-cache)
        (pixi-info)
        (pixi-info)
        (should (= calls 1))))))

(ert-deftest pixi-test-info-invalidate-clears-cache ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((calls 0))
      (cl-letf (((symbol-function 'call-process)
                 (lambda (&rest _)
                   (setq calls (1+ calls))
                   (insert "{\"version\":\"1.0\"}")
                   0)))
        (clrhash pixi--info-cache)
        (pixi-info)
        (pixi-info-invalidate)
        (pixi-info)
        (should (= calls 2))))))

(ert-deftest pixi-test-thin-readers-pull-from-info ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call
        (concat "{\"platform\":\"osx-arm64\",\"version\":\"0.70.0\","
                "\"project_info\":{\"name\":\"X\",\"version\":\"0.1.0\"},"
                "\"environments_info\":["
                "{\"name\":\"default\",\"tasks\":[\"build\",\"run\"]},"
                "{\"name\":\"dev\",\"tasks\":[\"build\",\"test\"]}"
                "]}")
        0
      (clrhash pixi--info-cache)
      (should (equal (pixi-platform)          "osx-arm64"))
      (should (equal (pixi-cli-version)       "0.70.0"))
      (should (equal (pixi-name)              "X"))
      (should (equal (pixi-version)           "0.1.0"))
      (should (equal (pixi-environment-names) '("default" "dev")))
      (should (equal (sort (pixi-tasks) #'string<)
                     '("build" "run" "test")))
      (should (equal (pixi-environment-tasks "dev") '("build" "test"))))))

(ert-deftest pixi-test-tasks-detailed-flattens-features ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call
        (concat "[{\"environment\":\"default\","
                "\"features\":["
                "{\"name\":\"build\",\"tasks\":["
                "{\"name\":\"build\",\"cmd\":\"colcon build\",\"depends_on\":[]}"
                "]},"
                "{\"name\":\"default\",\"tasks\":["
                "{\"name\":\"robot\",\"cmd\":\"ros2 run robot x\","
                "\"depends_on\":[{\"task_name\":\"build\"}]}"
                "]}]}]")
        0
      (let ((tasks (pixi-tasks-detailed)))
        (should (= (length tasks) 2))
        (let ((robot (seq-find (lambda (t) (equal "robot" (alist-get 'name t)))
                               tasks)))
          (should (equal (alist-get 'environment robot) "default"))
          (should (equal (alist-get 'feature     robot) "default"))
          (should (equal (pixi--task-depends-on robot) '("build"))))))))

(ert-deftest pixi-test-task-finds-by-name-and-env ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call
        (concat "[{\"environment\":\"default\","
                "\"features\":[{\"name\":\"f\",\"tasks\":["
                "{\"name\":\"build\",\"cmd\":\"a\",\"depends_on\":[]}]}]},"
                "{\"environment\":\"dev\","
                "\"features\":[{\"name\":\"f\",\"tasks\":["
                "{\"name\":\"build\",\"cmd\":\"b\",\"depends_on\":[]}]}]}]")
        0
      (should (equal (alist-get 'cmd (pixi-task "build" "default")) "a"))
      (should (equal (alist-get 'cmd (pixi-task "build" "dev"))     "b"))
      (should-not (pixi-task "nonexistent" "default")))))

(ert-deftest pixi-test-list-entries-shape ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call
        (concat "[{\"environment\":\"default\","
                "\"features\":[{\"name\":\"default\",\"tasks\":["
                "{\"name\":\"robot\",\"cmd\":\"ros2 run\","
                "\"depends_on\":[{\"task_name\":\"build\"}]}]}]}]")
        0
      (let* ((entries (pixi--task-list-entries))
             (row     (car entries))
             (id      (car row))
             (cols    (cadr row)))
        (should (= (length entries) 1))
        (should (equal id '("default" . "robot")))
        (should (= (length cols) 5))
        (should (equal (substring-no-properties (aref cols 0)) "robot"))
        (should (equal (substring-no-properties (aref cols 1)) "default"))
        (should (equal (substring-no-properties (aref cols 2)) ""))
        (should (equal (string-trim (substring-no-properties (aref cols 3))) "build"))
        (should (equal (substring-no-properties (aref cols 4)) "ros2 run"))
        (should (eq (get-text-property 1 'face (aref cols 3)) 'pixi-task-list-dep))))))

(ert-deftest pixi-test-list-entries-shows-non-default-env-pill ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call
        (concat "[{\"environment\":\"lyrical\","
                "\"features\":[{\"name\":\"build\",\"tasks\":["
                "{\"name\":\"build\",\"cmd\":\"colcon\",\"depends_on\":[]}]}]}]")
        0
      (let* ((row  (car (pixi--task-list-entries)))
             (envs (aref (cadr row) 2)))
        (should (equal (string-trim (substring-no-properties envs)) "lyrical"))
        (should (eq (get-text-property 1 'face envs) 'pixi-task-list-env))))))

(ert-deftest pixi-test-list-entries-dedupes-across-envs ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call
        (concat "[{\"environment\":\"default\","
                "\"features\":[{\"name\":\"build\",\"tasks\":["
                "{\"name\":\"build\",\"cmd\":\"colcon\",\"depends_on\":[]}]}]},"
                "{\"environment\":\"lyrical\","
                "\"features\":[{\"name\":\"build\",\"tasks\":["
                "{\"name\":\"build\",\"cmd\":\"colcon\",\"depends_on\":[]}]}]}]")
        0
      (let* ((entries (pixi--task-list-entries))
             (row     (car entries))
             (envs    (substring-no-properties (aref (cadr row) 2))))
        (should (= (length entries) 1))
        (should (equal (car row) '("build" . "build")))
        (should-not (string-match-p "default" envs))
        (should (string-match-p "lyrical" envs))))))

(ert-deftest pixi-test-platform-icon-dispatch ()
  (cl-letf* ((capture nil)
             ((symbol-function 'nerd-icons-faicon)
              (lambda (name &rest _) (setq capture (cons 'faicon name)) ""))
             ((symbol-function 'nerd-icons-mdicon)
              (lambda (name &rest _) (setq capture (cons 'mdicon name)) "")))
    (pixi--platform-icon "osx-arm64" 'vui-muted)
    (should (equal capture '(faicon . "nf-fa-apple")))
    (pixi--platform-icon "linux-64" 'vui-muted)
    (should (equal capture '(faicon . "nf-fa-linux")))
    (pixi--platform-icon "win-64" 'vui-muted)
    (should (equal capture '(faicon . "nf-fa-windows")))
    (pixi--platform-icon "freebsd-x86_64" 'vui-muted)
    (should (equal capture '(mdicon . "nf-md-monitor")))))

(ert-deftest pixi-test-clean-with-no-env-builds-command ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((captured nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t))
                ((symbol-function 'compile)
                 (lambda (cmd) (setq captured cmd))))
        (pixi-clean)
        (should captured)
        (should (string-match-p "\\bclean\\b" captured))
        (should-not (string-match-p "-e" captured))
        (should (string-match-p "--manifest-path" captured))))))

(ert-deftest pixi-test-clean-with-env-adds-env-flag ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((captured nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t))
                ((symbol-function 'compile)
                 (lambda (cmd) (setq captured cmd))))
        (pixi-clean "lyrical")
        (should (string-match-p "\\bclean\\b" captured))
        (should (string-match-p "-e lyrical" captured))))))

(ert-deftest pixi-test-clean-aborts-when-not-confirmed ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((compile-called nil))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) nil))
                ((symbol-function 'compile)
                 (lambda (_) (setq compile-called t))))
        (pixi-clean)
        (should-not compile-called)))))

(ert-deftest pixi-test-tree-bare ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((captured nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq captured cmd))))
        (pixi-tree)
        (should (string-match-p "\\btree\\b" captured))
        (should-not (string-match-p "-e " captured))
        (should (string-match-p "--manifest-path" captured))))))

(ert-deftest pixi-test-tree-with-env ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((captured nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq captured cmd))))
        (pixi-tree "lyrical")
        (should (string-match-p "tree -e lyrical" captured))))))

(ert-deftest pixi-test-tree-with-env-and-regex ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((captured nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq captured cmd))))
        (pixi-tree "default" "ros")
        (should (string-match-p "tree -e default ros" captured))))))

(ert-deftest pixi-test-tree-empty-regex-is-dropped ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (let ((captured nil))
      (cl-letf (((symbol-function 'compile) (lambda (cmd) (setq captured cmd))))
        (pixi-tree "default" "")
        (should (string-match-p "tree -e default --manifest-path" captured))))))

(ert-deftest pixi-test-packages-passes-environment ()
  (pixi-tests--with-workspace "pixi.toml" "[workspace]\n"
    (pixi-tests--with-mocked-call "[]" 0
      (pixi-packages "lyrical")
      (should (equal pixi-tests--captured-args
                     (list "list" "--json" "-e" "lyrical"
                           "--manifest-path" manifest))))))

(provide 'pixi-tests)

;;; pixi-tests.el ends here
