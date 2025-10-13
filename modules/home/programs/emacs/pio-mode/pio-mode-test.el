;;; platformio-mode-test.el -*- lexical-binding: t; -*-

(require 'ert)
(load (expand-file-name "pio-mode.el" (file-name-directory load-file-name)))

(ert-deftest platformio-greet-returns-string ()
  (should (string= (platformio-greet) "Hello from PlatformIO!")))
