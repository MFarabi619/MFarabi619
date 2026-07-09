;;; microvisor-process-compose.el --- Board integration  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/microvisor
;; Keywords: lisp, tools, convenience
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:
;; process-compose surface: `microvisor--process-compose-run'.
;;; Code:

(declare-function process-compose-declare "process-compose" (declaration))
(declare-function process-compose-reconcile "process-compose" ())
(declare-function process-compose-state "process-compose" (name))
(declare-function process-compose-ensure "process-compose" ())
(declare-function process-compose-start-process "process-compose" (name))
(declare-function process-compose-restart-process "process-compose" (name))
(declare-function process-compose-log-buffer "process-compose" (name))

(defun microvisor--process-compose-run (name namespace command &optional config)
  "Declare NAME under NAMESPACE running COMMAND, start it, show its log.
CONFIG, when non-nil, is an alist of raw process-compose keys folded into
the declaration.  Routes a picked `:process-compose' task to the board."
  (process-compose-declare
   (append (list :name name :namespace namespace :command command)
           (and config (list :config config))))
  (process-compose-ensure)
  (process-compose-reconcile)
  (if (process-compose-state name)
      (process-compose-restart-process name)
    (process-compose-start-process name))
  (display-buffer (process-compose-log-buffer name)))

(provide 'microvisor-process-compose)

;;; microvisor-process-compose.el ends here
