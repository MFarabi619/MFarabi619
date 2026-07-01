;;; ci-tests.el --- Buttercup tests for ci.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:  emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'ci)

(describe "ci--service-args"
  (it "wraps the command in a shell, tags it `ci', and carries group/label/icon"
    (let ((args (ci--service-args
                  '(:name "firmware build x" :group "firmware" :label "x"
                     :icon "nf-md-crane" :command "west build x"))))
      (expect (plist-get args :name) :to-equal "firmware build x")
      (expect (plist-get args :command) :to-equal shell-file-name)
      (expect (plist-get args :args)
        :to-equal (list shell-command-switch "west build x"))
      (expect (plist-get args :tags) :to-equal '(ci))
      (expect (plist-get args :group-label) :to-equal "firmware")
      (expect (plist-get args :display-name) :to-equal "x")
      (expect (plist-get args :ci-icon) :to-equal "nf-md-crane"))))

(describe "ci--job-status"
  (it "is queued when there is no process"
    (expect (ci--job-status '(:name "x")) :to-be 'queued))

  (it "is passed when the process exited zero"
    (assume (executable-find "true") "coreutils true needed")
    (let ((process (start-process "ci-test-pass" nil "true")))
      (while (process-live-p process) (accept-process-output process 0.05))
      (expect (ci--job-status (list :name "x" :process process)) :to-be 'passed)))

  (it "is failed when the process exited non-zero"
    (assume (executable-find "false") "coreutils false needed")
    (let ((process (start-process "ci-test-fail" nil "false")))
      (while (process-live-p process) (accept-process-output process 0.05))
      (expect (ci--job-status (list :name "x" :process process)) :to-be 'failed))))

(describe "ci--status-face"
  (it "maps each status to a vui semantic face"
    (expect (ci--status-face 'passed) :to-be 'vui-success)
    (expect (ci--status-face 'failed) :to-be 'vui-error)
    (expect (ci--status-face 'running) :to-be 'vui-warning)
    (expect (ci--status-face 'queued) :to-be 'vui-muted)))

(describe "ci--icon"
  (it "renders a non-empty glyph across nerd-icon families"
    (expect (length (ci--icon "nf-md-crane" 'vui-muted)) :to-be-greater-than 0)
    (expect (length (ci--icon "nf-seti-rust" 'vui-muted)) :to-be-greater-than 0)))

(describe "ci--badge"
  (it "renders the group's tool badge icon-only by default"
    (let ((ci-badge-show-label nil))
      (let ((badge (ci--badge '(:group-label "firmware"))))
        (expect (length badge) :to-be-greater-than 0)
        (expect (substring-no-properties badge) :not :to-match "west"))))
  (it "includes the label when `ci-badge-show-label' is non-nil"
    (let ((ci-badge-show-label t))
      (expect (substring-no-properties (ci--badge '(:group-label "firmware")))
        :to-match "west")))
  (it "returns nil for an unknown group"
    (expect (ci--badge '(:group-label "nope")) :to-be nil)))

(describe "ci--grouped-jobs"
  (it "groups services by :group following ci-jobs order"
    (let ((ci-jobs '((:name "a" :group "x") (:name "b" :group "y") (:name "c" :group "x"))))
      (spy-on 'prodigy-find-service :and-call-fake (lambda (n) (list :name n)))
      (let ((grouped (ci--grouped-jobs)))
        (expect (mapcar #'car grouped) :to-equal '("x" "y"))
        (expect (length (cdr (assoc "x" grouped))) :to-equal 2)
        (expect (length (cdr (assoc "y" grouped))) :to-equal 1)))))

(describe "ci--spinner"
  (it "returns one of the animation frames"
    (expect (seq-contains-p ci--spinner-frames (ci--spinner)) :to-be-truthy)))

(describe "ci--service-at-point"
  (it "reads the ci-service property from the current line"
    (with-temp-buffer
      (insert (propertize "row" 'ci-service '(:name "walter")) "\n")
      (goto-char (point-min))
      (expect (ci--service-at-point) :to-equal '(:name "walter"))))
  (it "returns nil on a line without the property"
    (with-temp-buffer
      (insert "plain\n")
      (goto-char (point-min))
      (expect (ci--service-at-point) :to-be nil))))

(describe "ci--mode-line-counts"
  (it "formats colored passed/failed/running/queued counts"
    (spy-on 'ci--jobs :and-return-value '(a b c))
    (spy-on 'ci--job-status
      :and-call-fake (lambda (s) (pcase s ('a 'passed) ('b 'failed) (_ 'queued))))
    (expect (substring-no-properties (ci--mode-line-counts)) :to-equal "[1/1/0/1]")))

(describe "ci-run-at-point"
  (it "starts the job at point and opens its log"
    (spy-on 'ci--service-at-point :and-return-value '(:name "walter"))
    (spy-on 'prodigy-start-service)
    (spy-on 'ci--display-log)
    (spy-on 'vui-refresh)
    (ci-run-at-point)
    (expect 'prodigy-start-service :to-have-been-called-with '(:name "walter"))
    (expect 'ci--display-log :to-have-been-called-with '(:name "walter"))))

(describe "ci-run-all"
  (it "starts every registered ci job"
    (let ((jobs '((:name "a") (:name "b"))))
      (spy-on 'ci--jobs :and-return-value jobs)
      (spy-on 'prodigy-start-service)
      (ci-run-all)
      (expect 'prodigy-start-service :to-have-been-called-with (nth 0 jobs))
      (expect 'prodigy-start-service :to-have-been-called-with (nth 1 jobs)))))

(describe "ci-rerun-failed"
  (it "restarts only the jobs whose derived status is failed"
    (let ((bad '(:name "bad")) (ok '(:name "ok")))
      (spy-on 'ci--jobs :and-return-value (list bad ok))
      (spy-on 'ci--job-status :and-call-fake (lambda (s) (if (eq s bad) 'failed 'passed)))
      (spy-on 'prodigy-start-service)
      (ci-rerun-failed)
      (expect 'prodigy-start-service :to-have-been-called-with bad)
      (expect (spy-calls-count 'prodigy-start-service) :to-equal 1))))

;;; ci-tests.el ends here
