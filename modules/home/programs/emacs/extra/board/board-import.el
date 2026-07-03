;;; board-import.el --- Generate board definitions from wokwi data  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/board
;; Keywords: tools, embedded, hardware
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;;; Code:

(require 'cl-lib)
(require 'seq)

(declare-function board-show "board" (board))
(declare-function consult--read "consult" (table &rest options))
(defvar board-buffer-name)

(defcustom board-import-wokwi-directory "~/workspace/wokwi-boards/boards"
  "Directory holding wokwi board definitions, one subdirectory per board."
  :type 'directory
  :group 'board)

;;; Reading

(defun board-import--read-board-json (file)
  "Parse the wokwi board.json FILE, tolerating JSONC comments."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (while (re-search-forward "/\\*\\(?:[^*]\\|\\*[^/]\\)*\\*/" nil t)
      (replace-match ""))
    (goto-char (point-min))
    (while (re-search-forward "^[[:blank:]]*//.*$" nil t)
      (replace-match ""))
    (goto-char (point-min))
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(defun board-import--physical-pins (board-json)
  "Return BOARD-JSON's header pins as plists.
Each pin is (:silkscreen NAME :x MM :y MM :target SIGNAL).
Virtual pins ($-prefixed) and positionless test pads are dropped."
  (cl-loop for (name . pin) in (alist-get 'pins board-json)
    for silkscreen = (symbol-name name)
    when (and (not (string-prefix-p "$" silkscreen))
           (alist-get 'x pin)
           (alist-get 'y pin))
    collect (list :silkscreen silkscreen
              :x (alist-get 'x pin)
              :y (alist-get 'y pin)
              :target (alist-get 'target pin))))

;;; Geometry

(defun board-import--sides (pins width)
  "Split PINS into (LEFT . RIGHT) against WIDTH's midline, top to bottom."
  (let ((sorted (seq-sort-by (lambda (pin) (plist-get pin :y)) #'< pins))
         (midline (/ width 2)))
    (cons
      (seq-filter (lambda (pin) (< (plist-get pin :x) midline)) sorted)
      (seq-filter (lambda (pin) (>= (plist-get pin :x) midline)) sorted))))

(defun board-import--number-pins (sides)
  "Return SIDES with physical pin numbers assigned counterclockwise."
  (let* ((left (car sides))
          (right (cdr sides))
          (total (+ (length left) (length right))))
    (cons
      (cl-loop for pin in left
        for number from 1
        collect (append (list :number number) pin))
      (cl-loop for pin in right
        for offset from 0
        collect (append (list :number (- total offset)) pin)))))

;;; Entry emission

(defun board-import--pin (pin)
  "Convert an imported PIN into a `board-definitions' pin plist."
  (let ((number (plist-get pin :number))
         (silkscreen (car (split-string (plist-get pin :silkscreen) "\\.")))
         (target (plist-get pin :target)))
    (if (string-prefix-p "GPIO" target)
      (list :number number :primary silkscreen :labels (list target))
      (list :number number :labels (list silkscreen)))))

(defun board-import-wokwi-board (file)
  "Read the wokwi board.json FILE into a `board-definitions' board."
  (let* ((board-json (board-import--read-board-json file))
          (sides (board-import--number-pins
                   (board-import--sides
                     (board-import--physical-pins board-json)
                     (alist-get 'width board-json)))))
    (list :name (alist-get 'name board-json)
      :sides (list (list 'left (mapcar #'board-import--pin (car sides)))
               (list 'right (mapcar #'board-import--pin (cdr sides)))))))

(defun board-import--board-json-file (name)
  "Return the board.json path for wokwi board NAME."
  (expand-file-name (file-name-concat name "board.json")
    board-import-wokwi-directory))

(defun board-import--available-boards ()
  "Return the wokwi board names under `board-import-wokwi-directory'."
  (seq-filter (lambda (name) (file-exists-p (board-import--board-json-file name)))
    (directory-files board-import-wokwi-directory nil (rx bos (not ".")))))

(defun board-import--preview-candidate (action candidate)
  "Render CANDIDATE's board on ACTION `preview'."
  (when (and (eq action 'preview) candidate)
    (ignore-errors
      (board-show (board-import-wokwi-board
                    (board-import--board-json-file candidate))))))

(defun board-import--read-board-name ()
  "Complete a wokwi board name, live-previewing each candidate.
Aborting restores the board that was displayed before."
  (let ((names (board-import--available-boards))
         (original (and (get-buffer board-buffer-name)
                     (buffer-local-value 'board--current
                       (get-buffer board-buffer-name)))))
    (if (not (fboundp 'consult--read))
      (completing-read "Wokwi board: " names nil t)
      (condition-case nil
        (consult--read names
          :prompt "Wokwi board: "
          :require-match t
          :preview-key 'any
          :state #'board-import--preview-candidate)
        (quit
          (when original (board-show original))
          (signal 'quit nil))))))

(defvar board-debug-mode)

(defun board-debug-wokwi-preview (name)
  "Render the imported board of the wokwi board NAME.
Hidden from \\[execute-extended-command] unless `board-debug-mode'."
  (interactive (list (board-import--read-board-name)))
  (board-show (board-import-wokwi-board (board-import--board-json-file name))))

(put 'board-debug-wokwi-preview 'completion-predicate
  (lambda (_symbol _buffer) board-debug-mode))

(defun board-import--entry-string (key board)
  "Render the BOARD plist as a `board-definitions' entry named KEY."
  (pcase-let ((`(:name ,name :sides ((left ,left) (right ,right))) board))
    (format "(%s\n  :name %S\n  :sides\n  ((left\n     (%s))\n    (right\n     (%s))))\n"
      key name
      (mapconcat #'prin1-to-string left "\n      ")
      (mapconcat #'prin1-to-string right "\n      "))))

;;;###autoload
(defun board-import-emit (name)
  "Insert the wokwi board NAME as a `board-definitions' entry at point.
Transcribes the geometry once; labels are then authored in place."
  (interactive (list (board-import--read-board-name)))
  (insert (board-import--entry-string
            (intern (replace-regexp-in-string "-" "_" name))
            (board-import-wokwi-board (board-import--board-json-file name)))))

(provide 'board-import)

;;; board-import.el ends here
