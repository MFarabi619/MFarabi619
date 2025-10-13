;;; pio-mode.el --- PlatformIO & Emacs integration -*- lexical-binding: t; -*-

;; Copyright (C) 2022, 2026 Mumtahin Farabi.
;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Maintainer: Mumtahin Farabi <mfarabi619@gmail.com>
;; Created: 13 Oct 2025
;;
;; This file is not part of GNU Emacs.
;;
;; Version: 0.0.1
;; Package-Version: 0.0.1
;; Keywords: c, hardware, processes, tools
;; Package-Requires: ((platformio-core "6.1.18"))
;; URL: https://github.com/MFarabi619/MFarabi619/tree/main/modules/home/programs/emacs/pio-mode

;;; Commentary:

;; PlatformIO is a modern alternative to the Arduino CLI, and is widely adopted in the embedded systems development ecosystem.
;; This package provides a guts-out, hackable integration with the modern "pio" CLI; with the goal of being a successor to `platformio-mode; with the goal of being a successor to `platformio-mode'.

;;; Change Log: Initial Release

;;; Code:

(defun pio-hello ()
  (interactive)
  (message "Hellooo from pio-mode!"))

(defvar pio-executable "platformio")

(define-derived-mode pio-system-info-mode tabulated-list-mode "PIO-System"
  (setq tabulated-list-format [("Field" 26 t) ("Value" 80 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(defun pio--sysinfo-entries-from-json (json-str)
  (let ((obj (json-parse-string json-str :object-type 'alist :array-type 'list)))
    (mapcar
     (lambda (pair)
       (let* ((k (car pair))
              (v (cdr pair))
              (title (alist-get 'title v))
              (val   (alist-get 'value v)))
         (list (symbol-name k) (vector title (format "%s" val)))))
     obj)))

(defun pio-system-info ()
  "Display `pio system info --json-output' in a grid."
  (interactive)
  (let* ((prog (or (executable-find pio-executable)
                   (user-error "pio not found: %s" pio-executable)))
         (buf (get-buffer-create "*PIO System Info*")))
    (with-current-buffer buf
      (pio-system-info-mode)
      (setq tabulated-list-entries nil)
      (setq-local pio--sysinfo-acc nil)
      (tabulated-list-print t))
    (pop-to-buffer buf)
    (make-process
     :name "pio-system-info"
     :buffer buf
     :command (list prog "system" "info" "--json-output")
     :filter (lambda (_p chunk)
               (with-current-buffer "*PIO System Info*"
                 (let ((inhibit-read-only t))
                   (setq-local pio--sysinfo-acc (concat (or pio--sysinfo-acc "") chunk)))))
     :sentinel (lambda (_p _e)
                 (with-current-buffer "*PIO System Info*"
                   (let* ((inhibit-read-only t)
                          (entries (pio--sysinfo-entries-from-json (or pio--sysinfo-acc "{}"))))
                     (setq tabulated-list-entries entries
                           pio--sysinfo-acc nil)
                     (tabulated-list-revert)))))))


(provide 'pio-mode)
;;; pio-mode.el ends here
