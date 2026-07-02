;;; board.el --- Board pinout diagrams  -*- lexical-binding: t -*-

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
(require 'face-remap)
(require 'vui)

;;; Customization

(defgroup board ()
  "Board pinout diagrams."
  :prefix "board-"
  :group 'tools
  :link '(url-link :tag "GitHub" "https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/board"))

(defconst board-buffer-name "*board*"
  "Name of the board diagram buffer.")

(defcustom board-body-width 51
  "Width in characters of the chip body, including both walls."
  :type 'natnum)

(defcustom board-row-spacing 4
  "Blank chip-body rows inserted between adjacent pin rows."
  :type 'natnum)

(defcustom board-lead-length 2
  "Length in characters of the lead between a pin's wall and its labels."
  :type 'natnum)

(defcustom board-default-board 'xiao_esp32s3
  "Key into `board-definitions' rendered by `board'."
  :type 'symbol)

(defcustom board-fit-fraction 0.80
  "Fraction of the window the auto-fit scale should target.
Lower values leave more breathing room around the diagram."
  :type 'number)

(defcustom board-max-scale 2.0
  "Upper bound on the auto-fit face-height scale."
  :type 'number)

(defcustom board-min-scale 0.6
  "Lower bound on the auto-fit face-height scale."
  :type 'number)

(defcustom board-definitions
  '((xiao_esp32s3
     :name "XIAO ESP32-S3"
     :usb (:type usb-c :side top)
     :sides
     ((left
       ((:number 1 :primary "D0" :labels ("ADC1/A0" "GPIO1" "RTC") :pwm t :touch t)
        (:number 2 :primary "D1" :labels ("ADC1/A1" "GPIO2" "RTC") :pwm t :touch t)
        (:number 3 :primary "D2" :labels ("ADC1/A2" "GPIO3" "RTC") :pwm t :touch t)
        (:number 4 :primary "D3" :labels ("ADC1/A3" "GPIO4" "RTC") :pwm t :touch t)
        (:number 5 :primary "D4" :labels ("ADC1/A4" "GPIO5" "RTC" "SDA1") :pwm t :touch t)
        (:number 6 :primary "D5" :labels ("ADC1/A5" "GPIO6" "RTC" "SCL1") :pwm t :touch t)
        (:number 7 :primary "D6" :labels ("GPIO43" "TX0") :pwm t)))
      (right
       ((:number 14 :labels ("VBUS"))
        (:number 13 :labels ("GND"))
        (:number 12 :labels ("3.3V-OUT"))
        (:number 11 :primary "D10" :labels ("ADC1/A10" "GPIO9" "RTC" "MOSI0") :pwm t :touch t)
        (:number 10 :primary "D9" :labels ("ADC1/A9" "GPIO8" "RTC" "MISO0") :pwm t :touch t)
        (:number 9 :primary "D8" :labels ("ADC1/A8" "GPIO7" "RTC" "SCK0") :pwm t :touch t)
        (:number 8 :primary "D7" :labels ("GPIO44" "RX0") :pwm t))))))
  "Board definitions, keyed by board symbol.
Each entry is (KEY . PLIST) where PLIST holds :name, :usb, and :sides.
:usb is (:type SYMBOL :side top|bottom).  :sides maps a side symbol
\(left, right) to a list of pin plists of the form
\(:number NUMBER :primary LABEL :labels (LABEL ...) :pwm BOOL :touch BOOL),
labels ordered innermost-first relative to the chip body.  :primary
is the vendor's own undisplayed pin name; its role tints the pin's
lead, wall connector, and touch glyph."
  :type 'sexp)

(defcustom board-show-legend t
  "Whether the role legend appears below the diagram."
  :type 'boolean)

;;; Model

(defun board-name (board)
  "Return the display name of BOARD."
  (plist-get board :name))

(defun board-side-pins (board side)
  "Return the pin plists on SIDE of BOARD."
  (car (alist-get side (plist-get board :sides))))

(defun board-pin-number (pin)
  "Return the physical pin number of PIN."
  (plist-get pin :number))

(defun board-pin-labels (pin)
  "Return the labels of PIN, innermost-first."
  (plist-get pin :labels))

(defun board-pin-pwm-p (pin)
  "Return non-nil when PIN is PWM-capable."
  (plist-get pin :pwm))

(defun board-pin-touch-p (pin)
  "Return non-nil when PIN is a capacitive-touch channel."
  (plist-get pin :touch))

(defun board-usb (board)
  "Return BOARD's USB connector spec, or nil."
  (plist-get board :usb))

;;; Roles

(defun board-label-role (label)
  "Return the role symbol for pin LABEL."
  (cond
   ((member label '("5V" "5V0" "3V3" "VDD" "VCC" "VBUS" "3.3V-OUT")) 'power)
   ((member label '("GND" "VSS")) 'ground)
   ((member label '("RTC" "RST" "EN")) 'system)
   ((string-match-p (rx bos "ADC" digit (or "/A" "_") (+ digit) eos) label) 'adc)
   ((string-match-p (rx bos (or "SDA" "SCL") (* digit) eos) label) 'i2c)
   ((string-match-p (rx bos (or "MOSI" "MISO" "SCK" "CS" "SS") (* digit) eos) label) 'spi)
   ((string-match-p (rx bos (or "TX" "RX" "RTS" "CTS") (* digit) eos) label) 'uart)
   ((string-match-p (rx bos "GPIO" (+ digit) eos) label) 'pin-name)
   (t 'gpio)))

;;; Faces

(defface board-power '((t :background "#e57373" :foreground "#1d2021" :weight bold))
  "Power rail labels.")

(defface board-ground '((t :background "#a89984" :foreground "#1d2021" :weight bold))
  "Ground labels.")

(defface board-gpio '((t :background "#9ccc65" :foreground "#1d2021" :weight bold))
  "Digital pin labels.")

(defface board-pin-name '((t :background "#a87858" :foreground "#1d2021" :weight bold))
  "Silicon pin-name labels.")

(defface board-adc '((t :background "#ff9800" :foreground "#1d2021" :weight bold))
  "ADC channel labels.")

(defface board-i2c '((t :background "#fabd2f" :foreground "#1d2021" :weight bold))
  "I2C signal labels.")

(defface board-spi '((t :background "#ba68c8" :foreground "#1d2021" :weight bold))
  "SPI signal labels.")

(defface board-uart '((t :background "#26a69a" :foreground "#1d2021" :weight bold))
  "UART signal labels.")

(defface board-system '((t :background "#8896a0" :foreground "#1d2021" :weight bold))
  "System pin labels.")

(defface board-usb '((t :background "#3c3836" :foreground "#ebdbb2" :weight bold))
  "USB connector pill.")

(defconst board--face-sources
  '((board-ground . nerd-icons-dsilver)
    (board-pin-name . nerd-icons-dmaroon)
    (board-adc . nerd-icons-orange)
    (board-i2c . nerd-icons-yellow)
    (board-spi . nerd-icons-purple)
    (board-uart . nerd-icons-dcyan)
    (board-system . nerd-icons-silver))
  "Map of role face to the nerd-icons face supplying its background.
Faces absent from this map keep their `defface' hex.")

(defun board--apply-theme-colors (&rest _)
  "Sync role-face backgrounds from their nerd-icons source faces.
Edge glyphs, leads, and walls follow automatically: their tints are
derived from these backgrounds at render time."
  (pcase-dolist (`(,face . ,source) board--face-sources)
    (let ((color (and (facep source)
                   (face-attribute source :foreground nil t))))
      (when (and (stringp color) (not (string-prefix-p "unspecified" color)))
        (set-face-attribute face nil :background color)))))

(board--apply-theme-colors)
(with-eval-after-load 'nerd-icons (board--apply-theme-colors))
(add-hook 'enable-theme-functions #'board--apply-theme-colors)

(defun board--role-face (role)
  "Return the face symbol for ROLE."
  (intern (format "board-%s" role)))

(defun board--role-tint (role)
  "Return a foreground-only face spec in ROLE's color."
  (list :foreground (face-attribute (board--role-face role) :background nil t)))

;;; Rendering

(defun board--pin-primary-role (pin)
  "Return the role of PIN's primary label.
The primary label is the vendor's own undisplayed pin name when
present (e.g. Seeed's D0), falling back to the innermost displayed
label.  Its role tints the pin's lead, wall connector, and touch
glyph."
  (board-label-role (or (plist-get pin :primary)
                      (car (board-pin-labels pin)))))

(defun board--label-chip (label)
  "Return LABEL as a slant-edged chip in its role face."
  (let* ((role (board-label-role label))
          (tint (board--role-tint role)))
    (concat (propertize "◥" 'face tint)
      (propertize (format " %s " label) 'face (board--role-face role))
      (propertize "◣" 'face tint))))

(defun board--labels-cell (pin side)
  "Return PIN's labels as one string of chips for SIDE.
Left-side labels are reversed so the innermost label sits next to
the chip body.  An absent PIN renders as an empty string."
  (if (null pin)
    ""
    (let ((labels (board-pin-labels pin)))
      (mapconcat #'board--label-chip
        (if (eq side 'left) (reverse labels) labels)))))

(defun board--body-span ()
  "Return the chip body width plus both lead margins."
  (+ board-body-width (* 2 board-lead-length)))

(defun board--lead (pin side)
  "Return PIN's lead line for SIDE, tinted by its primary role.
PWM pins draw a sine lead; touch pins carry the touch glyph in the
wall-adjacent position.  An absent PIN renders as blank margin."
  (if (null pin)
    (make-string board-lead-length ?\s)
    (let* ((lead-char (if (board-pin-pwm-p pin) ?∿ ?─))
            (touch-glyph (when (board-pin-touch-p pin)
                           (propertize "󰩕"
                             'face (append (board--role-tint 'gpio) '(:weight bold)))))
            (line (propertize
                    (make-string (- board-lead-length (if touch-glyph 1 0)) lead-char)
                    'face (board--role-tint (board--pin-primary-role pin)))))
      (cond
        ((null touch-glyph) line)
        ((eq side 'left) (concat line touch-glyph))
        (t (concat touch-glyph line))))))

(defun board--wall (pin connector-char)
  "Return the chip wall at PIN's row.
CONNECTOR-CHAR when PIN is present, tinted by its primary role; a
plain wall otherwise."
  (if pin
    (propertize (string connector-char)
      'face (board--role-tint (board--pin-primary-role pin)))
    "│"))

(defun board--pin-pill (pin)
  "Return PIN's number in a round pill, or an empty string.
Power and ground pins carry no pill."
  (if (or (null pin) (memq (board--pin-primary-role pin) '(power ground)))
    ""
    (let ((tint (board--role-tint 'gpio)))
      (concat (propertize "" 'face tint)
        (propertize (number-to-string (board-pin-number pin)) 'face 'board-gpio)
        (propertize "" 'face tint)))))

(defun board--body-cell (left-pin right-pin)
  "Return one chip-body row connecting LEFT-PIN and RIGHT-PIN.
Either pin may be nil, rendering a plain wall with no lead on that side."
  (let* ((left-pill (board--pin-pill left-pin))
          (right-pill (board--pin-pill right-pin))
          (walls-and-padding 4)
          (gap (- board-body-width walls-and-padding
                 (length left-pill) (length right-pill))))
    (concat (board--lead left-pin 'left)
      (board--wall left-pin ?┤)
      " " left-pill
      (make-string (max 1 gap) ?\s)
      right-pill " "
      (board--wall right-pin ?├)
      (board--lead right-pin 'right))))

(defun board--body-top-cell ()
  "Return the chip body's top edge, blank-margined for the leads."
  (let ((margin (make-string board-lead-length ?\s)))
    (concat margin "┌" (make-string (- board-body-width 2) ?─) "┐" margin)))

(defun board--body-bottom-cell (name)
  "Return the chip body's bottom edge with NAME centered in it."
  (let* ((margin (make-string board-lead-length ?\s))
          (label (format " %s " name))
          (fill (- board-body-width 2 (length label)))
          (left-fill (/ fill 2)))
    (concat margin
      "└"
      (make-string left-fill ?─)
      (propertize label 'face 'bold)
      (make-string (- fill left-fill) ?─)
      "┘"
      margin)))

(defun board--usb-label (usb)
  "Return the display label for the USB connector spec USB."
  (pcase (plist-get usb :type)
    ('usb-c "USB-C")
    ('usb-micro "uUSB")
    ('usb-mini "miniUSB")
    ('usb-a "USB-A")
    (type (upcase (symbol-name type)))))

(defun board--usb-cell (usb)
  "Return the USB connector pill centered over the chip span."
  (let* ((tint (list :foreground (face-attribute 'board-usb :background nil t)))
          (pill (concat (propertize "" 'face tint)
                  (propertize (format " %s " (board--usb-label usb)) 'face 'board-usb)
                  (propertize "" 'face tint)))
          (span (board--body-span)))
    (concat (make-string (board--centering-pad span (length pill)) ?\s) pill)))

(defconst board--legend-items
  '(("SYSTEM" . system)
    ("POWER" . power)
    ("GND" . ground)
    ("DIGITAL" . gpio)
    ("ADC INPUT" . adc)
    ("PIN NAME" . pin-name)
    ("SPI" . spi)
    ("UART" . uart)
    ("I2C" . i2c))
  "Legend chips in display order, as (LABEL . ROLE).")

(defun board--legend ()
  "Return the role legend as one line of chips."
  (mapconcat (pcase-lambda (`(,label . ,role))
               (propertize (format " %s " label) 'face (board--role-face role)))
    board--legend-items "  "))

(defun board--diagram (board)
  "Return BOARD's pinout diagram, legend included when `board-show-legend'."
  (let* ((left-pins (board-side-pins board 'left))
          (right-pins (board-side-pins board 'right))
          (usb (board-usb board))
          (row-count (max (length left-pins) (length right-pins)))
          (spacer-row (list "" (board--body-cell nil nil) ""))
          (usb-row (and usb (list "" (board--usb-cell usb) "")))
          (pin-rows
            (cl-loop for i below row-count
              for left-pin = (nth i left-pins)
              for right-pin = (nth i right-pins)
              for pin-row = (list (board--labels-cell left-pin 'left)
                             (board--body-cell left-pin right-pin)
                             (board--labels-cell right-pin 'right))
              if (< i (1- row-count))
              append (cons pin-row (make-list board-row-spacing spacer-row))
              else collect pin-row))
          (table
            (vui-table
              :columns '((:align :right) (:align :left) (:align :left))
              :rows (append
                      (when (and usb-row (eq (plist-get usb :side) 'top))
                        (list usb-row))
                      (list (list "" (board--body-top-cell) ""))
                      pin-rows
                      (list (list "" (board--body-bottom-cell (board-name board)) ""))
                      (when (and usb-row (eq (plist-get usb :side) 'bottom))
                        (list usb-row))))))
    (if board-show-legend
      (vui-vstack :spacing 1
        table
        (vui-box (vui-text (board--legend))
          :width (car (board--vnode-size table))
          :align :center))
      table)))

;;; Fit and centering

(defun board--centering-pad (available content)
  "Return the pad that centers CONTENT cells inside AVAILABLE cells."
  (max 0 (/ (- available content) 2)))

(defun board--fit-scale (canvas-columns canvas-rows pixel-width pixel-height char-width char-height)
  "Return the face-height scale fitting a CANVAS-COLUMNS × CANVAS-ROWS
diagram into a PIXEL-WIDTH × PIXEL-HEIGHT window whose unscaled
character cell is CHAR-WIDTH × CHAR-HEIGHT pixels.  Clamped to
[`board-min-scale', `board-max-scale'] and shrunk by `board-fit-fraction'."
  (let ((fit-width (* board-fit-fraction
                     (/ (/ (float pixel-width) char-width)
                       (max 1 canvas-columns))))
         (fit-height (* board-fit-fraction
                       (/ (/ (float pixel-height) char-height)
                         (max 1 canvas-rows)))))
    (max board-min-scale (min fit-width fit-height board-max-scale))))

(defun board--vnode-size (vnode)
  "Return VNODE's rendered size as (COLUMNS . ROWS).
VNODE must contain only plain vnodes, no components: measuring
renders into a temp buffer outside any component instance."
  (let ((lines (string-lines
                 (with-temp-buffer (vui-render vnode) (buffer-string)))))
    (cons (apply #'max 0 (mapcar #'length lines))
      (length lines))))

(defun board--center (vnode size total-columns total-rows)
  "Return VNODE of SIZE (COLUMNS . ROWS) centered in TOTAL-COLUMNS × TOTAL-ROWS."
  (let ((top-pad (board--centering-pad total-rows (cdr size)))
         (left-pad (board--centering-pad total-columns (car size))))
    (apply #'vui-fragment
      (append (make-list top-pad (vui-newline))
        (list (vui-vstack :indent left-pad vnode))))))

(defun board--apply-scale (scale)
  "Remap the buffer's default face height to SCALE."
  (if (= scale 1.0)
    (face-remap-reset-base 'default)
    (face-remap-set-base 'default `(:height ,scale) 'default)))

(defun board--display-window ()
  "Return the window showing the board buffer, or the selected window."
  (or (get-buffer-window board-buffer-name) (selected-window)))

(defun board--window-fit-scale (canvas-columns canvas-rows)
  "Return the auto-fit scale for the board buffer's window."
  (let ((window (board--display-window)))
    (board--fit-scale canvas-columns canvas-rows
      (window-body-width window t)
      (window-body-height window t)
      (max 1 (frame-char-width))
      (max 1 (frame-char-height)))))

;;; Component

(vui-defcomponent board-diagram (board)
  :render
  (let* ((diagram (board--diagram board))
          (size (board--vnode-size diagram))
          (window (board--display-window)))
    (board--apply-scale (board--window-fit-scale (car size) (cdr size)))
    (board--center diagram size
      (window-body-width window 'remap)
      (window-body-height window 'remap))))

;;; Entry point

(define-derived-mode board-mode vui-mode "board-mode"
  "Major mode for board pinout diagrams.")

;;;###autoload
(defun board ()
  "Open the pinout diagram for `board-default-board'."
  (interactive)
  (let ((board (alist-get board-default-board board-definitions)))
    (unless board
      (user-error "No board named %s in `board-definitions'" board-default-board))
    (with-current-buffer (get-buffer-create board-buffer-name)
      (unless (derived-mode-p 'board-mode) (board-mode)))
    (let ((instance (vui-mount (vui-component 'board-diagram :board board)
                      board-buffer-name)))
      (with-current-buffer board-buffer-name
        (vui-rerender-on-resize)
        (vui-rerender instance)))))

(provide 'board)

;;; board.el ends here
