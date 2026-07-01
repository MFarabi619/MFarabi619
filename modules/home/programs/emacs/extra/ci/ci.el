;;; ci.el --- Local-first CI + service orchestration over prodigy  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/ci
;; Keywords: tools, processes
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (prodigy "0.7") (vui "0.1") (nerd-icons "0.1"))

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'prodigy)
(require 'vui)
(require 'vui-components)
(require 'nerd-icons)

(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))

(defgroup ci ()
  "Local-first CI + service orchestration over prodigy."
  :prefix "ci-"
  :group 'tools)

(defcustom ci-root nil
  "Workspace root CI jobs run from.  When nil, the enclosing `.git' root."
  :type '(choice (const :tag "Auto-detect" nil) directory)
  :group 'ci)

(defcustom ci-jobs
  '((:name "firmware build qemu_riscv32"    :group "firmware" :label "qemu_riscv32"       :icon "nf-md-crane"
     :command "west build -b qemu_riscv32 -d build/qemu_riscv32 -p always apps/firmware")
    (:name "firmware build stm32f3_disco"   :group "firmware" :label "stm32f3_disco"      :icon "nf-md-crane"
     :command "west build -b stm32f3_disco@E/stm32f303xc -d build/stm32f3_disco -p always apps/firmware")
    (:name "firmware build walter"          :group "firmware" :label "walter"             :icon "nf-md-crane"
     :command "west build --sysbuild -b walter/esp32s3/procpu -d build/walter -p always apps/firmware")
    (:name "firmware build xiao"            :group "firmware" :label "xiao"               :icon "nf-md-crane"
     :command "west build --sysbuild -b xiao_esp32s3/esp32s3/procpu -d build/xiao -p always apps/firmware")
    (:name "firmware build xiao_sense"      :group "firmware" :label "xiao_sense"         :icon "nf-md-crane"
     :command "west build --sysbuild -b xiao_esp32s3/esp32s3/procpu/sense -d build/xiao_sense -p always apps/firmware")
    (:name "firmware build esp32s3_devkitc" :group "firmware" :label "esp32s3_devkitc"    :icon "nf-md-crane"
     :command "west build --sysbuild -b esp32s3_devkitc/esp32s3/procpu -d build/esp32s3_devkitc -p always apps/firmware")
    (:name "firmware build esp32_cyd"       :group "firmware" :label "esp32_cyd"          :icon "nf-md-crane"
     :command "west build -b esp32_devkitc/esp32/procpu -d build/esp32_cyd -p always apps/firmware")
    (:name "firmware test qemu_riscv32"     :group "firmware" :label "qemu_riscv32"        :icon "nf-md-beaker"
     :command "west build -b qemu_riscv32 -d build/qemu_riscv32-test -p always -t run apps/firmware -- -DEXTRA_CONF_FILE=test.conf")
    (:name "pio run ceratina"             :group "platformio" :label "ceratina"       :icon "nf-md-play"
     :command "pio run -e ceratina")
    (:name "cargo build firmware"         :group "cargo" :label "build firmware"      :icon "nf-md-crane"
     :command "cargo build --manifest-path apps/firmware/Cargo.toml")
    (:name "cargo loco doctor"            :group "cargo" :label "loco doctor"         :icon "nf-md-stethoscope"
     :command "cargo loco doctor")
    (:name "nix flake check"              :group "nix" :label "flake check"           :icon "nf-md-check_bold"
     :command "nix flake check")
    (:name "om health"                    :group "nix" :label "om health"            :icon "nf-md-heart_pulse"
     :command "om health"))
  "CI jobs.  Each is a plist of :name (unique), :group, :label, :icon, :command."
  :type '(repeat plist)
  :group 'ci)

(defcustom ci-group-badges
  '(("firmware"     "nf-md-kite"         nerd-icons-purple "west")
    ("platformio" "nf-seti-platformio" nerd-icons-yellow "platformio")
    ("cargo"      "nf-seti-rust"       nerd-icons-orange "cargo")
    ("nix"        "nf-md-nix"          nerd-icons-lblue  "nix")
    ("misc"       "nf-md-cog"          nerd-icons-silver "om"))
  "Trailing tool badge per job group, matching the compile-multi annotation.
Each entry is (GROUP ICON FACE LABEL)."
  :type '(repeat (list string string symbol string))
  :group 'ci)

(defcustom ci-badge-show-label nil
  "When non-nil, show a tool badge's label text beside its icon."
  :type 'boolean
  :group 'ci)

(defun ci--root ()
  "Return the directory CI jobs run from."
  (or ci-root (locate-dominating-file default-directory ".git") default-directory))

(defun ci--service-args (job)
  "Return the `prodigy-define-service' args for JOB (shared props via the `ci' tag).
A per-job :cwd overrides the tag's; jobs without one inherit `ci--root'."
  (append
   (list :name         (plist-get job :name)
         :command      shell-file-name
         :args         (list shell-command-switch (plist-get job :command))
         :tags         '(ci)
         :group-label  (plist-get job :group)
         :display-name (plist-get job :label)
         :ci-icon      (plist-get job :icon))
   (when (plist-get job :cwd) (list :cwd (plist-get job :cwd)))))

(defun ci--register-jobs ()
  "Define the `ci' tag and every `ci-jobs' entry as a prodigy service."
  (prodigy-define-tag
    :name 'ci
    :cwd (ci--root)
    :env '(("CLICOLOR_FORCE" "1") ("FORCE_COLOR" "1") ("TERM" "xterm-256color"))
    :stop-signal 'kill
    :kill-process-buffer-on-stop 'unless-visible)
  (dolist (job ci-jobs)
    (apply #'prodigy-define-service (ci--service-args job))))

(defun ci--jobs ()
  "Return the registered `ci'-tagged prodigy services."
  (prodigy-services-tagged-with 'ci))

(defun ci--grouped-jobs ()
  "Return ordered ((GROUP SERVICE...) ...) following `ci-jobs' order."
  (let ((result '()))
    (dolist (job ci-jobs)
      (when-let ((service (prodigy-find-service (plist-get job :name))))
        (let ((cell (assoc (plist-get job :group) result)))
          (if cell
              (setcdr cell (append (cdr cell) (list service)))
            (setq result (append result (list (list (plist-get job :group) service))))))))
    result))

(defun ci--job-status (service)
  "Derive SERVICE's CI status from its process: queued/running/passed/failed."
  (let ((process (plist-get service :process)))
    (cond
     ((null process) 'queued)
     ((process-live-p process) 'running)
     ((zerop (process-exit-status process)) 'passed)
     (t 'failed))))

(defun ci--status-face (status)
  "Return the face colouring a job's icon and label for CI STATUS."
  (pcase status
    ('running 'vui-warning)
    ('passed  'vui-success)
    ('failed  'vui-error)
    (_        'vui-muted)))

(defun ci--icon (name face)
  "Return nerd-icon NAME rendered in FACE."
  (funcall
   (cond
    ((string-prefix-p "nf-seti-" name) #'nerd-icons-sucicon)
    ((string-prefix-p "nf-dev-"  name) #'nerd-icons-devicon)
    ((string-prefix-p "nf-fa-"   name) #'nerd-icons-faicon)
    ((string-prefix-p "nf-cod-"  name) #'nerd-icons-codicon)
    (t #'nerd-icons-mdicon))
   name :face face))

(defun ci--badge (service)
  "Return the trailing tool-badge string for SERVICE, or nil.
The label is hidden unless `ci-badge-show-label' is non-nil."
  (when-let ((spec (cdr (assoc (plist-get service :group-label) ci-group-badges))))
    (let ((glyph (ci--icon (nth 0 spec) (nth 1 spec))))
      (if ci-badge-show-label
          (concat (propertize (nth 2 spec) 'face (nth 1 spec)) " " glyph)
        glyph))))

(defconst ci--spinner-frames ["⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷"]
  "Braille frames animated for running CI jobs.")

(defun ci--spinner ()
  "Return the current spinner frame, derived from the wall clock."
  (aref ci--spinner-frames
        (mod (truncate (* 8 (float-time))) (length ci--spinner-frames))))

(defun ci--service-at-point ()
  "Return the ci service whose row point is on, or nil."
  (save-excursion
    (beginning-of-line)
    (let ((end (line-end-position)) service)
      (while (and (not service) (< (point) end))
        (setq service (get-text-property (point) 'ci-service))
        (forward-char 1))
      service)))

(defun ci--mode-line-counts ()
  "Return a coloured [passed/failed/running/queued] mode-line segment."
  (let* ((statuses (mapcar #'ci--job-status (ci--jobs)))
         (n (lambda (status)
              (number-to-string (seq-count (lambda (s) (eq s status)) statuses)))))
    (concat "["
            (propertize (funcall n 'passed)  'face 'vui-success) "/"
            (propertize (funcall n 'failed)  'face 'vui-error)   "/"
            (propertize (funcall n 'running) 'face 'vui-warning) "/"
            (propertize (funcall n 'queued)  'face 'vui-muted)
            "]")))

;;;###autoload
(defun ci-run-all ()
  "Start every CI job."
  (interactive)
  (unless (ci--jobs) (ci--register-jobs))
  (mapc #'prodigy-start-service (ci--jobs))
  (when (derived-mode-p 'ci-mode) (vui-refresh)))

;;;###autoload
(defun ci-rerun-failed ()
  "Restart the CI jobs whose last run failed."
  (interactive)
  (mapc #'prodigy-start-service
        (seq-filter (lambda (service) (eq 'failed (ci--job-status service)))
                    (ci--jobs)))
  (when (derived-mode-p 'ci-mode) (vui-refresh)))

(defun ci--log-windows ()
  "Return windows currently showing a CI job's log buffer."
  (let ((names (mapcar #'prodigy-buffer-name (ci--jobs))))
    (seq-filter (lambda (window)
                  (member (buffer-name (window-buffer window)) names))
                (window-list))))

(defun ci--display-log (service)
  "Show SERVICE's log stacked beside the dashboard, not replacing other logs."
  (let ((buffer (get-buffer-create (prodigy-buffer-name service))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'prodigy-view-mode) (prodigy-view-mode)))
    (unless (get-buffer-window buffer)
      (let* ((log-windows (ci--log-windows))
             (ci-window   (get-buffer-window "*ci*"))
             (window (cond
                      (log-windows (split-window (car (last log-windows)) nil 'below))
                      (ci-window   (split-window ci-window nil 'right))
                      (t           (split-window)))))
        (set-window-buffer window buffer)
        (balance-windows)))))

(defun ci-run-at-point ()
  "Run the job at point and open its log."
  (interactive)
  (when-let ((service (ci--service-at-point)))
    (prodigy-start-service service)
    (ci--display-log service)
    (vui-refresh)))

(defun ci--row (service)
  "Return the vui table row for SERVICE."
  (let* ((status (ci--job-status service))
         (face   (ci--status-face status))
         (label  (or (plist-get service :display-name) (plist-get service :name))))
    (list
     (if (eq status 'running)
         (vui-text (ci--spinner) :face face)
       (vui-text (ci--icon (plist-get service :ci-icon) face)))
     (vui-text label :face face 'ci-service service)
     (vui-text (or (ci--badge service) "")))))

(vui-defcomponent ci-dashboard ()
  "Live dashboard for the `ci'-tagged prodigy services, grouped by tool."
  :render
  (let* ((statuses    (mapcar #'ci--job-status (ci--jobs)))
         (any-running (and (memq 'running statuses) t)))
    (vui-use-effect (any-running)
      (let ((timer (run-with-timer 0 (if any-running 0.1 1)
                                   (vui-with-async-context (vui-refresh)))))
        (lambda () (cancel-timer timer))))
    (apply #'vui-vstack
           (mapcan
            (lambda (group)
              (let ((name (car group)) (services (cdr group)))
                (list
                 (vui-text (format "%s (%d)" name (length services)) :face 'vui-heading-2)
                 (vui-table
                  :columns '((:width 2)
                             (:width 32 :grow t)
                             (:width 14))
                  :rows (mapcar #'ci--row services))
                 (vui-newline))))
            (ci--grouped-jobs)))))

(defvar ci-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "r") #'ci-run-at-point)
    (define-key map (kbd "g") #'vui-refresh)
    map)
  "Keymap for `ci-mode' buffers.")

(define-derived-mode ci-mode vui-mode "ci-mode"
  "Major mode for the `ci' dashboard."
  (setq mode-line-process '(" " (:eval (ci--mode-line-counts))))
  (when (fboundp 'evil-make-overriding-map)
    (evil-make-overriding-map ci-mode-map 'normal)))
(put 'ci-mode 'completion-predicate #'ignore)

(add-to-list 'nerd-icons-mode-icon-alist
             '(ci-mode nerd-icons-mdicon "nf-md-infinity" :face nerd-icons-lgreen))

;;;###autoload
(defun ci ()
  "Open the live CI dashboard for the current workspace."
  (interactive)
  (unless (ci--jobs) (ci--register-jobs))
  (let ((buffer (get-buffer-create "*ci*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ci-mode) (ci-mode)))
    (vui-mount (vui-component 'ci-dashboard) "*ci*")
    (pop-to-buffer-same-window buffer)))

(provide 'ci)

;;; ci.el ends here
