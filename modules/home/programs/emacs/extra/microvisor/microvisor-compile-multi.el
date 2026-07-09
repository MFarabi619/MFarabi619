;;; microvisor-compile-multi.el --- Picker integration  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/microvisor
;; Keywords: lisp, tools, convenience
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (compile-multi "0.7") (nerd-icons "0.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:
;; compile-multi surface: `microvisor-task', annotation tint, `microvisor-run'.
;;; Code:

(require 'compile-multi)
(require 'nerd-icons)
(require 'microvisor)
(require 'microvisor-process-compose)

;;; Display metadata

(defcustom microvisor-tool-display
  '(("cargo"      "\U0000E7A8" . nerd-icons-orange)
    ("west"       "\U000F1985" . nerd-icons-purple)
    ("dioxus"     "\U0000ED7D" . nerd-icons-blue)
    ("platformio" "\U0000E682" . nerd-icons-yellow)
    ("nix"        "\U0000E843" . nerd-icons-lblue)
    ("pulumi"     "\U0000E873" . nerd-icons-purple)
    ("emacs"      "\U0000E7CF" . nerd-icons-dpurple)
    ("pacman"     "\U0000E732" . nerd-icons-blue)
    ("apt"        "\U0000E77D" . nerd-icons-dred)
    ("pkg_add"    "\U0000F328" . nerd-icons-yellow)
    ("pkg"        "\U000F08E0" . nerd-icons-red)
    ("guix"       "\U0000F325" . nerd-icons-yellow))
  "Alist mapping a task's :tool label to (GLYPH . FACE) for its annotation."
  :type '(alist :key-type string
                :value-type (cons string symbol))
  :group 'microvisor)

(defun microvisor-icon-face (tool)
  "Return the annotation face for the TOOL label, or nil if not registered."
  (cddr (assoc tool microvisor-tool-display)))

(defcustom microvisor-namespace-icons
  '(("loco"        . "\U0000E3C3")
    ("west"        . "\U000F1985")
    ("web"         . "\U0000ED7D")
    ("ceratina"    . "\U0000E682")
    ("flake"       . "\U000F1105")
    ("nix"         . "\U000F1105")
    ("microvisor"  . "\U000F1105")
    ("pulumi"      . "\U0000E873")
    ("microtop"    . "\U000F056E")
    ("buttercup"   . "\U0000E7CF")
    ("tui"         . "\U0000EBC8")
    ("firmware"    . "\U0000F2DB")
    ("esp32s3"     . "\U0000F4BC")
    ("esp32"       . "\U0000EC19")
    ("stm32h723zg" . "\U000F0697"))
  "Alist mapping a namespace to the glyph shown beside its group header."
  :type '(alist :key-type string :value-type string)
  :group 'microvisor)

(defun microvisor--namespace-label (namespace)
  "Return NAMESPACE flanked on both sides by its group glyph, if registered."
  (if-let* ((glyph (alist-get namespace microvisor-namespace-icons
                              nil nil #'equal)))
      (concat glyph " " namespace " " glyph)
    namespace))

;;; Task conversion

(defun microvisor-task (task)
  "Format producer TASK into a native `compile-multi' task.
Bakes the flanked namespace glyph, icon, and name into the title; marks a
`:runner daemon' task `:process-compose' with its `:config'; turns `:tool'
into a tinted annotation."
  (let ((title (concat (microvisor--namespace-label (plist-get task :namespace))
                       ":"
                       (when-let* ((icon (plist-get task :icon)))
                         (concat icon " "))
                       (plist-get task :name))))
    (append (list title :command (plist-get task :command))
            (when (eq (plist-get task :runner) 'daemon)
              (list :process-compose (or (plist-get task :config) t)))
            (when-let* ((tool (plist-get task :tool)))
              (list :annotation
                    (if-let* ((glyph (cadr (assoc tool microvisor-tool-display))))
                        (concat tool " " glyph)
                      tool))))))

(defun microvisor--annotation-tool (annotation)
  "Return the `microvisor-tool-display' key named by ANNOTATION text, if any."
  (when-let* ((word (car (split-string (or annotation "")))))
    (and (assoc word microvisor-tool-display) word)))

(defun microvisor--compile-multi-annotation-advice (original task)
  "Tint ORIGINAL's annotation for TASK by its `:annotation' tool face."
  (when-let* ((annotation (funcall original task)))
    (when-let* ((tool (microvisor--annotation-tool
                       (plist-get (cdr task) :annotation)))
                (face (microvisor-icon-face tool)))
      (setq annotation (copy-sequence annotation))
      (put-text-property 0 (length annotation) 'face face annotation))
    annotation))

(unless (advice-member-p #'microvisor--compile-multi-annotation-advice
                         'compile-multi--annotation-function)
  (advice-add 'compile-multi--annotation-function
              :around #'microvisor--compile-multi-annotation-advice))

(declare-function process-compose-state "process-compose" (name))
(declare-function process-compose--status-class "process-compose" (state))
(declare-function process-compose--status-face "process-compose" (status-class))
(declare-function process-compose--spinner "process-compose" ())
(defvar process-compose--transitional-statuses)

(defun microvisor--process-status (title)
  "Return (FACE . LEAD) for TITLE's live process-compose state, or nil.
LEAD is a spinner frame for a transitional status, else a plain margin space."
  (when-let* ((state (process-compose-state (microvisor--slug title))))
    (cons (process-compose--status-face (process-compose--status-class state))
          (if (member (gethash "status" state) process-compose--transitional-statuses)
              (process-compose--spinner)
            " "))))

(defun microvisor--group-margin-advice (original cand transform)
  "Left-pad and status-tint ORIGINAL's display for CAND when TRANSFORM is set."
  (let ((result (funcall original cand transform)))
    (if (and transform (stringp result))
        (if-let* ((status (microvisor--process-status cand)))
            (let ((row (concat (cdr status) result)))
              (add-face-text-property 0 (length row) (car status) nil row)
              row)
          (concat " " result))
      result)))

(unless (advice-member-p #'microvisor--group-margin-advice
                         'compile-multi--group-function)
  (advice-add 'compile-multi--group-function
              :around #'microvisor--group-margin-advice))

;;; Launcher

(defvar vertico-multiform-commands)
(defvar microvisor-picker-width)

(defun microvisor--register-picker-display ()
  "Register the task picker's side window in `vertico-multiform-commands'."
  (when (boundp 'vertico-multiform-commands)
    (setf (alist-get 'microvisor-run vertico-multiform-commands)
          `(buffer
            (vertico-buffer-display-action
             . ((display-buffer-reuse-window display-buffer-in-side-window)
                (side . right)
                (window-width . ,microvisor-picker-width)
                (window-parameters . ((no-delete-other-windows . t)
                                      (mode-line-format . none)))))))))

(defcustom microvisor-picker-width 35
  "Width of the task-picker side window.
A float is a fraction of the frame width; an integer is a column count.
Set it declaratively: `setq' it before microvisor loads, or `setopt' it
after (both re-register the display); customize is not required."
  :type 'number
  :set (lambda (symbol value)
         (set-default symbol value)
         (microvisor--register-picker-display))
  :group 'microvisor)

(declare-function vertico-posframe-mode "vertico-posframe" (&optional arg))
(defvar vertico-posframe-mode)

(declare-function compile-multi--get-task "compile-multi" ())

(defun microvisor--run-task ()
  "Pick a `compile-multi' task and dispatch it by kind.
A task marked `:process-compose' starts on the process-compose board; a
function command is called; a string command compiles."
  (let* ((default-directory (or (and compile-multi-default-directory
                                     (funcall compile-multi-default-directory))
                                default-directory))
         (task (or (compile-multi--get-task)
                   (user-error "Microvisor: no task selected")))
         (command (plist-get (cdr task) :command)))
    (cond
     ((plist-get (cdr task) :process-compose)
      (let* ((title (car task))
             (colon (or (string-search ":" title) (length title)))
             (namespace (microvisor--slug (substring title 0 colon)))
             (config (plist-get (cdr task) :process-compose)))
        (microvisor--process-compose-run
         (microvisor--slug title) namespace command
         (and (consp (car-safe config)) config))))
     ((functionp command) (funcall command))
     ((stringp command)
      (let ((compilation-environment
             (append '("FORCE_COLOR=1" "CLICOLOR_FORCE=1" "CARGO_TERM_COLOR=always")
                     compilation-environment)))
        (compile command)))
     (t (user-error "Microvisor: task has no runnable command")))))

(declare-function vertico--exhibit "vertico" ())
(defvar process-compose--states-updated-hook)
(defvar microvisor--picker-timer nil
  "Timer redrawing the open picker so spinners and status faces animate.")

(defun microvisor--refresh-picker (&rest _)
  "Redraw the open vertico picker so live status faces and spinners update."
  (when-let* ((window (active-minibuffer-window)))
    (with-selected-window window
      (when (fboundp 'vertico--exhibit)
        (vertico--exhibit)))))

(defun microvisor--picker-refresh (enable)
  "Turn the picker's live-status refresh on when ENABLE, else off."
  (if enable
      (progn
        (add-hook 'process-compose--states-updated-hook #'microvisor--refresh-picker)
        (setq microvisor--picker-timer
              (run-with-timer 0.1 0.1 #'microvisor--refresh-picker)))
    (remove-hook 'process-compose--states-updated-hook #'microvisor--refresh-picker)
    (when microvisor--picker-timer
      (cancel-timer microvisor--picker-timer)
      (setq microvisor--picker-timer nil))))

;;;###autoload
(defun microvisor-run ()
  "Pick and run a task; `:process-compose' tasks run on process-compose.
Suspends `vertico-posframe-mode' while picking, and keeps the picker's
process status faces and spinners live for the duration."
  (interactive)
  (let ((posframe (bound-and-true-p vertico-posframe-mode)))
    (when posframe (vertico-posframe-mode -1))
    (microvisor--picker-refresh t)
    (unwind-protect (microvisor--run-task)
      (microvisor--picker-refresh nil)
      (when posframe (vertico-posframe-mode 1)))))

(with-eval-after-load 'vertico-multiform
  (microvisor--register-picker-display))

(provide 'microvisor-compile-multi)

;;; microvisor-compile-multi.el ends here
