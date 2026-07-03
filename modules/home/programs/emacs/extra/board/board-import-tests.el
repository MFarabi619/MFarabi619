;;; board-import-tests.el --- Buttercup tests for board-import.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'seq)
(require 'board)
(require 'board-import)

(buttercup-error-on-stale-elc)

(defconst board-import-tests--fixtures
  (expand-file-name "fixtures"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Fixture mirrors of the upstream source trees.")

(setq board-zephyr-root
  (expand-file-name "zephyr" board-import-tests--fixtures)
  board-hal-espressif-root
  (expand-file-name "hal_espressif" board-import-tests--fixtures)
  board-arduino-variants-root
  (expand-file-name "framework-arduinoespressif32/variants"
    board-import-tests--fixtures))

(defconst board-import-tests--xiao-fixture
  (expand-file-name "fixtures/wokwi-boards/boards/xiao-esp32-s3/board.json"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Byte-identical copy of wokwi-boards' xiao-esp32-s3/board.json.")

(describe "board-import--read-board-json"
  :var* ((board-json (board-import--read-board-json board-import-tests--xiao-fixture)))

  (it "parses the file despite JSONC block comments"
    (expect (alist-get 'name board-json) :to-equal "Seeed Studio XIAO ESP32-S3")
    (expect (alist-get 'width board-json) :to-equal 18.1))

  (it "keeps virtual pins in the raw data"
    (expect (alist-get '$gpio21 (alist-get 'pins board-json)) :to-be-truthy)))

(describe "board-import--physical-pins"
  :var* ((pins (board-import--physical-pins
                 (board-import--read-board-json board-import-tests--xiao-fixture))))

  (it "returns the fourteen physical pins, excluding virtual nets"
    (expect (length pins) :to-equal 14))

  (it "carries silkscreen name, position, and target"
    (let ((first-pin (car pins)))
      (expect (plist-get first-pin :silkscreen) :to-equal "D0")
      (expect (plist-get first-pin :target) :to-equal "GPIO1")
      (expect (plist-get first-pin :x) :to-equal 1.4335))))

(describe "board-import--sides"
  :var* ((board-json (board-import--read-board-json board-import-tests--xiao-fixture))
          (sides (board-import--sides
                   (board-import--physical-pins board-json)
                   (alist-get 'width board-json)))
          (silkscreens (lambda (pins)
                         (mapcar (lambda (pin) (plist-get pin :silkscreen)) pins))))

  (it "clusters pins left of the midline, top to bottom"
    (expect (funcall silkscreens (car sides))
      :to-equal '("D0" "D1" "D2" "D3" "D4" "D5" "D6")))

  (it "clusters pins right of the midline, top to bottom"
    (expect (funcall silkscreens (cdr sides))
      :to-equal '("5V" "GND" "3V3" "D10" "D9" "D8" "D7"))))

(describe "board-import--number-pins"
  :var* ((board-json (board-import--read-board-json board-import-tests--xiao-fixture))
          (numbered (board-import--number-pins
                      (board-import--sides
                        (board-import--physical-pins board-json)
                        (alist-get 'width board-json))))
          (numbers (lambda (pins)
                     (mapcar (lambda (pin) (plist-get pin :number)) pins))))

  (it "numbers the left side top to bottom"
    (expect (funcall numbers (car numbered)) :to-equal '(1 2 3 4 5 6 7)))

  (it "continues counterclockwise up the right side"
    (expect (funcall numbers (cdr numbered)) :to-equal '(14 13 12 11 10 9 8))))

(describe "board-import-wokwi-board (golden fixture)"
  :var* ((board (board-import-wokwi-board board-import-tests--xiao-fixture))
          (resolved (board--lookup 'xiao_esp32s3)))

  (it "reproduces the resolved entry's pin numbering on both sides"
    (dolist (side '(left right))
      (expect (mapcar #'board-pin-number (board-side-pins board side))
        :to-equal (mapcar #'board-pin-number (board-side-pins resolved side)))))

  (it "reproduces the resolved entry's vendor pin names"
    (dolist (side '(left right))
      (expect (mapcar (lambda (pin) (plist-get pin :primary))
                (board-side-pins board side))
        :to-equal (mapcar (lambda (pin) (plist-get pin :primary))
                    (board-side-pins resolved side)))))

  (it "maps every vendor-named pin to the same GPIO as the resolved entry"
    (dolist (side '(left right))
      (cl-mapc (lambda (board-pin resolved-pin)
                 (when (plist-get board-pin :primary)
                   (expect (board-pin-labels resolved-pin)
                     :to-contain (car (board-pin-labels board-pin)))))
        (board-side-pins board side)
        (board-side-pins resolved side))))

  (it "labels power pins with their silkscreen names"
    (expect (mapcar #'board-pin-labels (seq-take (board-side-pins board 'right) 3))
      :to-equal '(("5V") ("GND") ("3V3")))))

(describe "board-import-wokwi-board (devkitc fixture)"
  :var* ((board (board-import-wokwi-board
                     (expand-file-name "fixtures/wokwi-boards/boards/esp32-s3-devkitc-1/board.json"
                       (file-name-directory (or load-file-name buffer-file-name))))))

  (it "numbers 22 left pins down and 22 right pins up"
    (expect (mapcar #'board-pin-number (board-side-pins board 'left))
      :to-equal (number-sequence 1 22))
    (expect (mapcar #'board-pin-number (board-side-pins board 'right))
      :to-equal (nreverse (number-sequence 23 44))))

  (it "strips dedup suffixes from repeated silkscreen names"
    (expect (board-pin-labels (car (board-side-pins board 'left)))
      :to-equal '("3V3"))
    (expect (board-pin-labels (car (last (board-side-pins board 'right))))
      :to-equal '("GND")))

  (it "labels the reset pin from its silkscreen, not its target"
    (expect (board-pin-labels (nth 2 (board-side-pins board 'left)))
      :to-equal '("RST"))))

(describe "board-debug-wokwi-preview"
  (it "is an interactive command"
    (expect (commandp #'board-debug-wokwi-preview) :to-be-truthy))

  (it "stays out of M-x completion until board-debug-mode is enabled"
    (let ((predicate (get 'board-debug-wokwi-preview 'completion-predicate)))
      (let ((board-debug-mode nil))
        (expect (funcall predicate 'board-debug-wokwi-preview (current-buffer))
          :to-be nil))
      (let ((board-debug-mode t))
        (expect (funcall predicate 'board-debug-wokwi-preview (current-buffer))
          :to-be-truthy))))

  (it "offers only directories that contain a board.json"
    (let* ((board-import-wokwi-directory (make-temp-file "wokwi" t)))
      (make-directory (expand-file-name "some-board" board-import-wokwi-directory))
      (with-temp-file (expand-file-name "some-board/board.json"
                        board-import-wokwi-directory)
        (insert "{}"))
      (make-directory (expand-file-name "not-a-board" board-import-wokwi-directory))
      (expect (board-import--available-boards) :to-equal '("some-board")))))

(describe "board-import--read-board-json comments"
  (it "strips whole-line comments without harming URLs in strings"
    (let ((file (make-temp-file "jsonc" nil ".json"
                  "{\n  // a comment\n  \"url\": \"https://wokwi.com\"\n}")))
      (expect (alist-get 'url (board-import--read-board-json file))
        :to-equal "https://wokwi.com"))))

(describe "board-import--physical-pins test pads"
  (it "drops positionless test pads that are not header pins"
    (let ((pins (board-import--physical-pins
                  '((pins . ((GP0 . ((x . 1.6) (y . 3.4) (target . "GPIO0")))
                              (TP4 . ((target . "GPIO23")))))))))
      (expect (length pins) :to-equal 1)
      (expect (plist-get (car pins) :silkscreen) :to-equal "GP0"))))

(describe "board-import-emit"
  (it "transcribes a wokwi board into readable board-definitions Lisp"
    (let* ((board (board-import-wokwi-board board-import-tests--xiao-fixture))
            (entry (car (read-from-string
                          (board-import--entry-string 'xiao_test board)))))
      (expect (car entry) :to-be 'xiao_test)
      (expect (plist-get (cdr entry) :name)
        :to-equal (plist-get board :name))
      (expect (plist-get (cdr entry) :sides)
        :to-equal (plist-get board :sides))))

  (it "inserts the entry at point, keyed by an underscored name"
    (cl-letf (((symbol-function 'board-import--board-json-file)
                (lambda (_) board-import-tests--xiao-fixture)))
      (with-temp-buffer
        (board-import-emit "xiao-esp32-s3")
        (goto-char (point-min))
        (expect (buffer-string) :to-match "^(xiao_esp32_s3\n")
        (expect (car (read (current-buffer))) :to-be 'xiao_esp32_s3)))))

(provide 'board-import-tests)

;;; board-import-tests.el ends here
