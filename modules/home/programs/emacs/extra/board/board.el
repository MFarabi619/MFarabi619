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
(require 'text-property-search)
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

(defcustom board-definitions
  '((xiao_esp32s3
     :zephyr-board "seeed/xiao_esp32s3"
     :arduino-variant "XIAO_ESP32S3"
     :usb (:type usb-c :side top)
     :left (D0 D1 D2 D3 D4 D5 D6)
     :right (VBUS GND 3V3-OUT D10 D9 D8 D7))
    (esp32s3_devkitc1
     :name "ESP32-S3-DevKitC-1"
     :zephyr-board "espressif/esp32s3_devkitc"
     :arduino-variant "esp32s3"
     :usb (:type usb-micro :side bottom)
     :row-spacing 1
     :left (3V3 3V3 RST GPIO4 GPIO5 GPIO6 GPIO7 GPIO15 GPIO16 GPIO17
             GPIO18 GPIO8 GPIO3 GPIO46 GPIO9 GPIO10 GPIO11 GPIO12
             GPIO13 GPIO14 5V GND)
     :right (GND GPIO43 GPIO44 GPIO1 GPIO2 GPIO42 GPIO41 GPIO40 GPIO39
              GPIO38 GPIO37 GPIO36 GPIO35 GPIO0 GPIO45 GPIO48 GPIO47
              GPIO21 GPIO20 GPIO19 GND GND)))
  "Board definitions, keyed by board symbol.
Each entry is (KEY . PLIST).  A pinout entry holds :left and :right
— ordered pin keys, top to bottom — resolved against the sources:
:zephyr-board names the boards/VENDOR/BOARD directory supplying the
name, chip, connector map, and bus roles; :arduino-variant names
the pins_arduino.h supplying touch pads.  Pin keys are connector
names (D0), GPIO names (GPIO4), or silkscreen labels (GND).  :usb
is (:type SYMBOL :side top|bottom); :row-spacing overrides
`board-row-spacing'; :name overrides the board.yml full name.
A prerendered entry holds :name and :sides — (SIDE (PIN ...)) with
pin plists (:number N :primary LABEL :labels (LABEL ...) :pwm BOOL
:touch BOOL), labels innermost-first; :primary is the vendor's own
undisplayed pin name."
  :type 'sexp)

(defcustom board-show-legend t
  "Whether the role legend appears below the diagram."
  :type 'boolean)

;;; Sources

(defcustom board-zephyr-root "~/workspace/zephyrproject/zephyr"
  "Zephyr repository that pinout entries are resolved from."
  :type 'directory)

(defcustom board-hal-espressif-root
  "~/workspace/zephyrproject/modules/hal/espressif"
  "Espressif HAL module holding the per-chip silicon tables."
  :type 'directory)

(defcustom board-arduino-variants-root
  "~/.platformio/packages/framework-arduinoespressif32/variants"
  "Arduino variants directory holding pins_arduino.h files."
  :type 'directory)

(defun board--file-matches (file regexp collect)
  "Return COLLECT of each REGEXP match in FILE; nil when FILE is missing."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let (matches)
        (while (re-search-forward regexp nil t)
          (push (funcall collect) matches))
        (nreverse matches)))))

(defun board--zephyr-board-directory (zephyr-board)
  "Return ZEPHYR-BOARD's directory under `board-zephyr-root'."
  (expand-file-name (file-name-concat "boards" zephyr-board)
    board-zephyr-root))

(defun board--board-yml (directory)
  "Return DIRECTORY's board.yml facts as (:full-name NAME :chip CHIP)."
  (let ((file (expand-file-name "board.yml" directory)))
    (list
      :full-name (car (board--file-matches file "full_name: \\(.+\\)$"
                        (lambda () (match-string 1))))
      :chip (car (board--file-matches file "- name: \\(.+\\)$"
                   (lambda () (match-string 1)))))))

(defun board--connector-gpios (directory)
  "Return DIRECTORY's connector map as an alist of index to GPIO number."
  (cl-loop for file in (directory-files directory t "\\.dtsi\\'")
    append (board--file-matches file
             "<\\([0-9]+\\) 0 &gpio\\([01]\\) \\([0-9]+\\) 0>"
             (lambda ()
               (cons (string-to-number (match-string 1))
                 (+ (* 32 (string-to-number (match-string 2)))
                   (string-to-number (match-string 3))))))))

(defun board--pinctrl-signals (directory)
  "Return DIRECTORY's pinctrl as an alist of GPIO number to signal names."
  (let ((file (expand-file-name
                (concat (file-name-nondirectory directory) "-pinctrl.dtsi")
                directory))
         (signals nil))
    (dolist (match (board--file-matches file
                     "<\\([A-Z0-9_]+\\)_GPIO\\([0-9]+\\)>"
                     (lambda ()
                       (cons (string-to-number (match-string 2))
                         (match-string 1)))))
      (push (cdr match) (alist-get (car match) signals)))
    (mapcar (lambda (cell) (cons (car cell) (nreverse (cdr cell))))
      signals)))

(defun board--adc-labels (chip)
  "Return CHIP's ADC channels as an alist of GPIO number to label."
  (board--file-matches
    (expand-file-name
      (file-name-concat "components/soc" chip "include/soc/adc_channel.h")
      board-hal-espressif-root)
    "#define ADC\\([12]\\)_CHANNEL_\\([0-9]+\\)_GPIO_NUM +\\([0-9]+\\)"
    (lambda ()
      (cons (string-to-number (match-string 3))
        (format "ADC%s_%s" (match-string 1) (match-string 2))))))

(defun board--rtc-gpios (chip)
  "Return CHIP's RTC-domain GPIO numbers."
  (board--file-matches
    (expand-file-name
      (file-name-concat "components/soc" chip "include/soc/rtc_io_channel.h")
      board-hal-espressif-root)
    "RTCIO_GPIO\\([0-9]+\\)_CHANNEL"
    (lambda () (string-to-number (match-string 1)))))

(defun board--arduino-touch-gpios (variant)
  "Return VARIANT's touch-pad GPIO numbers from its pins_arduino.h."
  (when variant
    (board--file-matches
      (expand-file-name (file-name-concat variant "pins_arduino.h")
        board-arduino-variants-root)
      "uint8_t T[0-9]+ = \\([0-9]+\\);"
      (lambda () (string-to-number (match-string 1))))))

(defcustom board-label-style 'zephyr
  "Naming convention for bus label chips.
`zephyr' keeps the pinmux signal names (UART0_TX); `arduino'
renders the familiar short forms (TX0)."
  :type '(choice (const zephyr) (const arduino)))

(defconst board--pinmux-chip-labels
  '(("\\`UART\\([0-9]\\)_TX\\'" . "TX\\1")
     ("\\`UART\\([0-9]\\)_RX\\'" . "RX\\1")
     ("\\`I2C\\([0-9]\\)_SDA\\'" . "SDA\\1")
     ("\\`I2C\\([0-9]\\)_SCL\\'" . "SCL\\1")
     ("\\`SPIM\\([0-9]\\)_MISO\\'" . "MISO\\1")
     ("\\`SPIM\\([0-9]\\)_MOSI\\'" . "MOSI\\1")
     ("\\`SPIM\\([0-9]\\)_SCLK\\'" . "SCK\\1")
     ("\\`SPIM\\([0-9]\\)_CSEL\\'" . "CS\\1")
     ("\\`TWAI_TX\\'" . "CAN_TX")
     ("\\`TWAI_RX\\'" . "CAN_RX"))
  "Pinmux signals that render as label chips; other signals stay silent.")

(defun board--signal-chip-label (signal)
  "Return SIGNAL's label chip text, or nil for silent signals.
`board-label-style' picks between the signal name itself and its
Arduino short form."
  (cl-loop for (regexp . replacement) in board--pinmux-chip-labels
    when (string-match regexp signal)
    return (if (eq board-label-style 'arduino)
             (replace-match replacement t nil signal)
             signal)))

(defun board--resolve-pin (key number connector signals adc rtc touch)
  "Resolve pin KEY at NUMBER against the parsed source tables.
CONNECTOR, SIGNALS, ADC, RTC, and TOUCH are the alists and GPIO
lists returned by the source parsers."
  (let* ((name (symbol-name key))
          (gpio (cond
                  ((string-match "\\`D\\([0-9]+\\)\\'" name)
                    (alist-get (string-to-number (match-string 1 name))
                      connector))
                  ((string-match "\\`GPIO\\([0-9]+\\)\\'" name)
                    (string-to-number (match-string 1 name))))))
    (if (null gpio)
      (list :number number :labels (list name))
      (append
        (list :number number)
        (when (string-prefix-p "D" name) (list :primary name))
        (list :labels
          (append
            (list (format "GPIO%d" gpio))
            (delq nil (mapcar #'board--signal-chip-label
                        (alist-get gpio signals)))
            (when (memq gpio rtc) (list "RTC"))
            (when-let* ((label (alist-get gpio adc))) (list label))))
        (list :pwm t)
        (when (memq gpio touch) (list :touch t))))))

(defvar board--resolved (make-hash-table :test 'equal)
  "Resolved pinout entries, keyed by (BOARD-SYMBOL . LABEL-STYLE).")

(defvar board--current-key nil
  "Key of the board most recently looked up.")

(defun board--resolve (entry)
  "Resolve the pinout ENTRY into a full board plist via the sources."
  (let* ((directory (board--zephyr-board-directory
                      (plist-get entry :zephyr-board)))
          (board-yml (board--board-yml directory))
          (connector (board--connector-gpios directory))
          (signals (board--pinctrl-signals directory))
          (adc (board--adc-labels (plist-get board-yml :chip)))
          (rtc (board--rtc-gpios (plist-get board-yml :chip)))
          (touch (board--arduino-touch-gpios
                   (plist-get entry :arduino-variant)))
          (left-keys (plist-get entry :left))
          (right-keys (plist-get entry :right))
          (total (+ (length left-keys) (length right-keys))))
    (append
      (list :name (or (plist-get entry :name)
                    (plist-get board-yml :full-name)))
      (when-let* ((usb (plist-get entry :usb))) (list :usb usb))
      (when-let* ((spacing (plist-get entry :row-spacing)))
        (list :row-spacing spacing))
      (list :sides
        (list
          (list 'left
            (cl-loop for pin-key in left-keys
              for number from 1
              collect (board--resolve-pin pin-key number connector
                        signals adc rtc touch)))
          (list 'right
            (cl-loop for pin-key in right-keys
              for offset from 0
              collect (board--resolve-pin pin-key (- total offset)
                        connector signals adc rtc touch))))))))

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

(defun board--row-spacing (board)
  "Return BOARD's row spacing, defaulting to `board-row-spacing'."
  (or (plist-get board :row-spacing) board-row-spacing))

;;; Roles

(defun board-label-role (label)
  "Return the role symbol for pin LABEL."
  (cond
   ((member label '("5V" "5V0" "3V3" "VDD" "VCC" "VBUS" "3V3-OUT")) 'power)
   ((member label '("GND" "VSS")) 'ground)
   ((member label '("RTC" "RST" "EN")) 'system)
   ((string-match-p (rx bos "ADC" digit (or "/A" "_") (+ digit) eos) label) 'adc)
   ((string-match-p (rx bos (or "SDA" "SCL") (* digit) eos) label) 'i2c)
   ((string-match-p (rx bos "I2C" digit "_" (or "SDA" "SCL") eos) label) 'i2c)
   ((string-match-p (rx bos (or "MOSI" "MISO" "SCK" "CS" "SS") (* digit) eos) label) 'spi)
   ((string-match-p (rx bos "SPIM" digit "_"
                      (or "MISO" "MOSI" "SCLK" "CSEL") eos) label) 'spi)
   ((string-match-p (rx bos (or "TX" "RX" "RTS" "CTS") (* digit) eos) label) 'uart)
   ((string-match-p (rx bos "UART" digit "_"
                      (or "TX" "RX" "RTS" "CTS") eos) label) 'uart)
   ((string-match-p (rx bos "U" digit (or "TXD" "RXD" "RTS" "CTS") eos) label) 'uart)
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

(defface board-hover '((t :background "#fabd2f"))
  "Label chip under the mouse.
Only the background is used: the hover overlays paint it behind the
chip body and as the slant glyphs' foreground.")

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

(defvar-keymap board-chip-map
  :doc "Keymap active on label chips."
  "RET" #'board-describe-pin
  "<mouse-1>" #'board-describe-pin)

(defun board--labels-cell (pin side)
  "Return PIN's labels as one string of chips for SIDE.
Left-side labels are reversed so the innermost label sits next to
the chip body.  Each chip carries a distinct help-echo describing
it (which also delimits the chip for hover and navigation), the pin
itself, and the chip keymap.  An absent PIN renders as an empty
string."
  (if (null pin)
    ""
    (mapconcat
      (lambda (label)
        (propertize (board--label-chip label)
          'help-echo (format "Pin %d · %s · %s"
                       (board-pin-number pin) label (board-label-role label))
          'board-pin pin
          'keymap board-chip-map))
      (let ((labels (board-pin-labels pin)))
        (if (eq side 'left) (reverse labels) labels)))))

(defun board--lead-width ()
  "Return the lead width in characters: the lead plus the touch slot."
  (1+ board-lead-length))

(defun board--body-span ()
  "Return the chip body width plus both lead margins."
  (+ board-body-width (* 2 (board--lead-width))))

(defun board--lead (pin side)
  "Return PIN's lead for SIDE, tinted by its primary role.
PWM pins draw a sine lead.  Touch pins place the touch glyph against
the wall ahead of the lead; plain pins draw one more lead character
instead.  An absent PIN renders as blank margin."
  (if (null pin)
    (make-string (board--lead-width) ?\s)
    (let* ((touch-pin-p (board-pin-touch-p pin))
            (line (propertize
                    (make-string
                      (if touch-pin-p board-lead-length (board--lead-width))
                      (if (board-pin-pwm-p pin) ?∿ ?─))
                    'face (board--role-tint (board--pin-primary-role pin))))
            (glyph (when touch-pin-p
                     (propertize "󰩕"
                       'face (append (board--role-tint 'gpio) '(:weight bold))))))
      (cond
        ((null glyph) line)
        ((eq side 'left) (concat line glyph))
        (t (concat glyph line))))))

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
  (let ((margin (make-string (board--lead-width) ?\s)))
    (concat margin "┌" (make-string (- board-body-width 2) ?─) "┐" margin)))

(defun board--body-bottom-cell (name)
  "Return the chip body's bottom edge with NAME centered in it."
  (let* ((margin (make-string (board--lead-width) ?\s))
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

(defun board--gap-count (board)
  "Return the number of gaps between BOARD's adjacent pin rows."
  (1- (max (length (board-side-pins board 'left))
        (length (board-side-pins board 'right)))))

(defun board--distribute (total gap-count cap)
  "Distribute TOTAL blank rows over GAP-COUNT pin gaps, at most CAP each.
Returns a list of GAP-COUNT counts, the remainder given to the earliest
gaps so short-changed pairs collect at the bottom."
  (when (> gap-count 0)
    (let* ((total (min total (* gap-count cap)))
            (base (/ total gap-count))
            (remainder (% total gap-count)))
      (cl-loop for slot below gap-count
        collect (+ base (if (< slot remainder) 1 0))))))

(defun board--diagram (board &optional row-spacing)
  "Return BOARD's pinout diagram, legend included when `board-show-legend'.
ROW-SPACING may be nil (the board's preferred spacing), an integer
\(uniform spacing), or a list of per-gap blank row counts as
produced by `board--distribute'."
  (let* ((left-pins (board-side-pins board 'left))
          (right-pins (board-side-pins board 'right))
          (gaps (if (integerp row-spacing)
                  (make-list (board--gap-count board) row-spacing)
                  (or row-spacing
                    (make-list (board--gap-count board)
                      (board--row-spacing board)))))
          (usb (board-usb board))
          (spacer-row (list "" (board--body-cell nil nil) ""))
          (usb-row (and usb (list "" (board--usb-cell usb) "")))
          (pin-rows
            (cl-loop while (or left-pins right-pins)
              for left-pin = (pop left-pins)
              for right-pin = (pop right-pins)
              for pin-row = (list (board--labels-cell left-pin 'left)
                             (board--body-cell left-pin right-pin)
                             (board--labels-cell right-pin 'right))
              if (or left-pins right-pins)
              append (cons pin-row
                       (make-list (or (pop gaps) 0) spacer-row))
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

(defun board--vnode-size (vnode)
  "Return VNODE's rendered size as (COLUMNS . ROWS).
VNODE must contain only plain vnodes, no components."
  (let ((lines (string-lines
                 (with-temp-buffer (vui-render vnode) (buffer-string)))))
    (cons (apply #'max 0 (mapcar #'string-width lines))
      (length lines))))

(defun board--center (vnode size total-columns total-rows)
  "Return VNODE of SIZE (COLUMNS . ROWS) centered in TOTAL-COLUMNS × TOTAL-ROWS."
  (let ((top-pad (board--centering-pad total-rows (cdr size)))
         (left-pad (board--centering-pad total-columns (car size))))
    (apply #'vui-fragment
      (append (make-list top-pad (vui-newline))
        (list (vui-vstack :indent left-pad vnode))))))

(defun board--display-window ()
  "Return the window showing the board buffer on any frame.
Falls back to the selected window before the buffer is first
displayed."
  (or (get-buffer-window board-buffer-name t) (selected-window)))

(defun board--layout (board window-rows)
  "Lay BOARD out to fit WINDOW-ROWS.
Measures the dense diagram, spreads the spare rows over the pin
gaps (capped at the board's preferred spacing), and trims by
re-measurement until it fits.  Returns (DIAGRAM . CANVAS-SIZE),
CANVAS-SIZE being the fitting measurement."
  (let* ((gap-count (board--gap-count board))
          (dense-rows (cdr (board--vnode-size (board--diagram board 0))))
          (gap-budget (max 0 (- window-rows dense-rows)))
          (gaps (board--distribute gap-budget gap-count
                  (board--row-spacing board)))
          (diagram (board--diagram board gaps))
          (canvas-size (board--vnode-size diagram)))
    (cl-loop while (and (> (cdr canvas-size) window-rows) (> gap-budget 0))
      do (setq gap-budget (1- gap-budget)
           gaps (board--distribute gap-budget gap-count
                  (board--row-spacing board))
           diagram (board--diagram board gaps)
           canvas-size (board--vnode-size diagram)))
    (cons diagram canvas-size)))

;;; Hover

(defvar-local board--hover-overlays nil
  "Overlays painting the label chip under the mouse.")

(defun board--clear-hover ()
  "Remove the hover overlays."
  (mapc #'delete-overlay board--hover-overlays)
  (setq board--hover-overlays nil))

(defun board--chip-bounds (position)
  "Return (START . END) of the label chip at POSITION, or nil.
A chip is one contiguous run of the same help-echo value."
  (when (get-text-property position 'help-echo)
    (cons (or (previous-single-property-change (1+ position) 'help-echo)
            (point-min))
      (or (next-single-property-change position 'help-echo)
        (point-max)))))

(defun board--apply-hover (start end)
  "Paint the chip between START and END in the hover color.
The body gets a hover background merged over its text; the slant
glyphs get a hover foreground so they read as the parallelogram's
outer tips."
  (let ((hover-color (face-attribute 'board-hover :background nil t))
         (body (make-overlay (1+ start) (1- end)))
         (left-edge (make-overlay start (1+ start)))
         (right-edge (make-overlay (1- end) end)))
    (overlay-put body 'face (list :background hover-color))
    (overlay-put left-edge 'face (list :foreground hover-color))
    (overlay-put right-edge 'face (list :foreground hover-color))
    (setq board--hover-overlays (list body left-edge right-edge))))

(defun board-follow-mouse (event)
  "Move the chip hover highlight to the chip under the mouse EVENT."
  (interactive "e" board-mode)
  (when-let* ((buffer (get-buffer board-buffer-name)))
    (with-current-buffer buffer
      (board--clear-hover)
      (let* ((start (event-start event))
              (window (posn-window start))
              (position (posn-point start)))
        (when (and (windowp window)
                (eq (window-buffer window) buffer)
                (numberp position)
                (< position (point-max)))
          (when-let* ((bounds (board--chip-bounds position)))
            (board--apply-hover (car bounds) (cdr bounds))))))))

;;; Pin interaction

(defun board-describe-pin (&optional event)
  "Echo the description of the chip at point, or under the mouse EVENT."
  (interactive (list last-input-event) board-mode)
  (let ((position (if (consp event)
                    (posn-point (event-start event))
                    (point))))
    (if-let* ((description (get-text-property position 'help-echo)))
      (message "%s" description)
      (user-error "No pin here"))))

(defun board-next-chip ()
  "Move point to the next label chip and highlight it."
  (interactive nil board-mode)
  (if-let* ((match (text-property-search-forward 'help-echo nil nil t)))
    (progn
      (goto-char (prop-match-beginning match))
      (board--clear-hover)
      (board--apply-hover (prop-match-beginning match) (prop-match-end match)))
    (message "No next chip")))

(defun board-previous-chip ()
  "Move point to the previous label chip and highlight it."
  (interactive nil board-mode)
  (if-let* ((match (text-property-search-backward 'help-echo nil nil t)))
    (progn
      (goto-char (prop-match-beginning match))
      (board--clear-hover)
      (board--apply-hover (prop-match-beginning match) (prop-match-end match)))
    (message "No previous chip")))

(defun board--eldoc-at-point (callback &rest _)
  "Describe the label chip at point through eldoc's CALLBACK."
  (when-let* ((description (get-text-property (point) 'help-echo)))
    (funcall callback description)))

(defun board--imenu-create-index ()
  "Return one imenu entry per pin in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (let (index)
      (while-let ((match (text-property-search-forward 'board-pin)))
        (let ((pin (prop-match-value match)))
          (push (cons (format "Pin %d (%s)"
                        (board-pin-number pin)
                        (car (board-pin-labels pin)))
                  (prop-match-beginning match))
            index)))
      (nreverse index))))

(defun board--hide-cursor ()
  "Hide the cursor, including evil's per-state cursors."
  (setq-local cursor-type nil
    cursor-in-non-selected-windows nil)
  (dolist (symbol '(evil-normal-state-cursor
                     evil-insert-state-cursor
                     evil-visual-state-cursor
                     evil-motion-state-cursor
                     evil-operator-state-cursor
                     evil-replace-state-cursor
                     evil-emacs-state-cursor))
    (when (boundp symbol)
      (set (make-local-variable symbol) '(bar . 0))))
  (when (fboundp 'evil-refresh-cursor)
    (evil-refresh-cursor)))

(defun board--hide-cursor-after-evil ()
  "Re-hide the cursor once evil finishes its state setup.
Evil activates in `after-change-major-mode-hook', after the mode
body runs; a zero-delay timer fires after that."
  (let ((buffer (current-buffer)))
    (run-at-time 0 nil
      (lambda ()
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (board--hide-cursor)))))))

;;; Component

(defvar-local board--layout-window-cells nil
  "(WIDTH . HEIGHT) of the window body the last layout was computed for.")

(defun board--refit-if-window-changed ()
  "Re-render once when the window changed since the layout was computed."
  (when-let* ((window (get-buffer-window (current-buffer) t)))
    (unless (equal board--layout-window-cells
              (cons (window-body-width window t)
                (window-body-height window t)))
      (vui-refresh))))

(vui-defcomponent board-diagram (board)
  :on-mount (board--refit-if-window-changed)
  :on-update (board--refit-if-window-changed)
  :render
  (pcase-let* ((window (board--display-window))
                (window-cells (cons (window-body-width window t)
                                (window-body-height window t)))
                (`(,diagram . ,canvas-size)
                  (board--layout board (cdr window-cells))))
    (setq board--layout-window-cells window-cells)
    (board--center diagram canvas-size
      (car window-cells) (cdr window-cells))))

;;; Entry point

(defvar-keymap board-mode-map
  :doc "Keymap for `board-mode'."
  "/" #'board-switch
  "TAB" #'board-next-chip
  "<backtab>" #'board-previous-chip
  "<mouse-movement>" #'board-follow-mouse)

(define-minor-mode board-debug-mode
  "Expose board debugging commands."
  :global t)

(defvar board--current)

(defun board-debug ()
  "Show the layout arithmetic for the current board in this window."
  (interactive nil board-mode)
  (pcase-let* ((window (get-buffer-window (current-buffer) t))
                (window-columns (window-body-width window t))
                (window-rows (window-body-height window t))
                (board board--current)
                (`(,dense-columns . ,dense-rows)
                  (board--vnode-size (board--diagram board 0)))
                (`(,_ . (,columns . ,rows))
                  (board--layout board window-rows)))
    (message (concat "window %d×%d · legend %s · dense %d×%d · spare %d"
               " · spent %d over %d gaps · final %d×%d %s")
      window-columns window-rows (if board-show-legend "on" "off")
      dense-columns dense-rows (- window-rows dense-rows)
      (- rows dense-rows) (board--gap-count board)
      columns rows (if (and (<= columns window-columns)
                         (<= rows window-rows))
                     "fits" "OVER"))))

(defun board-toggle-label-style ()
  "Toggle bus labels between Zephyr signal names and Arduino short forms."
  (interactive nil board-mode)
  (setq board-label-style
    (if (eq board-label-style 'zephyr) 'arduino 'zephyr))
  (when board--current-key
    (board-show (board--lookup board--current-key))))

(defun board-toggle-legend ()
  "Toggle the legend beneath the diagram."
  (interactive nil board-mode)
  (setq board-show-legend (not board-show-legend))
  (vui-refresh))

(define-derived-mode board-mode vui-mode "board-mode"
  "Major mode for board pinout diagrams."
  (setq-local track-mouse t
    truncate-lines t
    line-spacing 0
    imenu-create-index-function #'board--imenu-create-index)
  (add-hook 'eldoc-documentation-functions #'board--eldoc-at-point nil t)
  (add-hook 'window-configuration-change-hook
    #'board--refit-if-window-changed nil t)
  (eldoc-mode 1)
  (board--hide-cursor)
  (board--hide-cursor-after-evil))

(put 'board-mode 'completion-predicate #'ignore)

(unless read-extended-command-predicate
  (setq read-extended-command-predicate #'command-completion-default-include-p))

(defun board--lookup (key)
  "Return the resolved board plist for KEY, or signal a `user-error'."
  (let ((entry (or (alist-get key board-definitions)
                 (user-error "No board named %s in `board-definitions'" key))))
    (setq board--current-key key)
    (if (plist-get entry :sides)
      entry
      (let ((cache-key (cons key board-label-style)))
        (or (gethash cache-key board--resolved)
          (puthash cache-key (board--resolve entry) board--resolved))))))

(defvar-local board--current nil
  "The board plist currently displayed in this buffer.")

(defun board--invoking-window ()
  "Return the window the current command was invoked from.
During minibuffer input, the window selected before it opened."
  (let ((window (or (minibuffer-selected-window) (selected-window))))
    (if (window-minibuffer-p window) (get-largest-window) window)))

(defun board-show (board)
  "Display BOARD, a board plist, in the board buffer.
Pinout entries are resolved first; a buried board takes over the
invoking window without selecting it."
  (unless (plist-get board :sides)
    (setq board (board--resolve board)))
  (with-current-buffer (get-buffer-create board-buffer-name)
    (unless (derived-mode-p 'board-mode) (board-mode))
    (setq board--current board
      mode-name (format "board[%s]" (board-name board))))
  (if-let* ((instance (vui-get-instance board-buffer-name)))
    (progn
      (unless (get-buffer-window board-buffer-name t)
        (set-window-buffer (board--invoking-window) board-buffer-name))
      (vui-update instance (list :board board)))
    (let ((instance (vui-mount (vui-component 'board-diagram :board board)
                      board-buffer-name)))
      (with-current-buffer board-buffer-name
        (vui-rerender-on-resize)
        (vui-rerender instance)))))

;;;###autoload
(defun board ()
  "Open the pinout diagram for `board-default-board'."
  (interactive)
  (board-show (board--lookup board-default-board))
  (select-window (get-buffer-window board-buffer-name t)))

(defun board-switch (key)
  "Switch the board diagram to KEY from `board-definitions'."
  (interactive
    (list (intern (completing-read "Board: " board-definitions nil t)))
    board-mode)
  (board-show (board--lookup key)))

(require 'board-import)

(provide 'board)

;;; board.el ends here
