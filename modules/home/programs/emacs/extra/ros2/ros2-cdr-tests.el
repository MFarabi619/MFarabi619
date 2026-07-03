;;; ros2-cdr-tests.el --- tests for the CDR decoder -*- lexical-binding: t; -*-

;;; Commentary:
;; Decodes REAL payloads captured off the bridge (fixtures/*.hex) against the
;; schemas the bridge advertised (fixtures/ros2-advertise.json), asserting the
;; values rclpy's own deserializer produced for those exact bytes.

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'seq)
(require 'json)
(require 'ros2-cdr)

(defconst ros2-cdr-tests--fixtures
  (expand-file-name "fixtures"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun ros2-cdr-tests--hex-bytes (name)
  "Read fixtures/NAME (a hex string) into a unibyte byte string."
  (let* ((hex (with-temp-buffer
                (insert-file-contents (expand-file-name name ros2-cdr-tests--fixtures))
                (string-trim (buffer-string))))
         (count (/ (length hex) 2)))
    (apply #'unibyte-string
           (cl-loop for i below count
                    collect (string-to-number (substring hex (* 2 i) (+ 2 (* 2 i))) 16)))))

(defun ros2-cdr-tests--schema (topic)
  "Return the ros2msg schema text the advertise fixture carries for TOPIC."
  (let* ((data (with-temp-buffer
                 (insert-file-contents
                  (expand-file-name "ros2-advertise.json" ros2-cdr-tests--fixtures))
                 (json-parse-buffer :object-type 'alist :array-type 'list)))
         (channel (seq-find (lambda (c) (equal (alist-get 'topic c) topic))
                            (alist-get 'channels data))))
    (alist-get 'schema channel)))

(defun ros2-cdr-tests--get (msg &rest keys)
  "Walk nested alist MSG following string KEYS."
  (dolist (key keys msg)
    (setq msg (alist-get key msg nil nil #'equal))))

(describe "ros2-cdr-decode NavSatFix (real /gps/fix capture)"
  (let (msg)
    (before-all
      (setq msg (ros2-cdr-decode (ros2-cdr-tests--schema "/gps/fix")
                                 (ros2-cdr-tests--hex-bytes "ros2-navsatfix.hex"))))
    (it "decodes the nested Header (Time + string)"
      (expect (ros2-cdr-tests--get msg "header" "frame_id") :to-equal "base_link")
      (expect (ros2-cdr-tests--get msg "header" "stamp" "sec") :to-equal 1782926126))
    (it "decodes the nested NavSatStatus (int8 then uint16, forcing a pad byte)"
      (expect (ros2-cdr-tests--get msg "status" "status") :to-equal 0)
      (expect (ros2-cdr-tests--get msg "status" "service") :to-equal 1))
    (it "decodes the float64 scalars"
      (expect (ros2-cdr-tests--get msg "latitude") :to-be-close-to 45.4215 4)
      (expect (ros2-cdr-tests--get msg "longitude") :to-be-close-to -75.6972 4))
    (it "decodes the fixed float64[9] array and the trailing enum"
      (expect (ros2-cdr-tests--get msg "position_covariance")
              :to-equal '(1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 4.0))
      (expect (ros2-cdr-tests--get msg "position_covariance_type") :to-equal 2))))

(describe "ros2-cdr-decode BatteryState (real /battery capture)"
  (let (msg)
    (before-all
      (setq msg (ros2-cdr-decode (ros2-cdr-tests--schema "/battery")
                                 (ros2-cdr-tests--hex-bytes "ros2-batterystate.hex"))))
    (it "decodes float32 scalars"
      (expect (ros2-cdr-tests--get msg "voltage") :to-be-close-to 12.6853 3)
      (expect (ros2-cdr-tests--get msg "percentage") :to-be-close-to 0.98779 4))
    (it "decodes bool and uint8 enum fields"
      (expect (ros2-cdr-tests--get msg "present") :to-be-truthy)
      (expect (ros2-cdr-tests--get msg "power_supply_status") :to-equal 2)
      (expect (ros2-cdr-tests--get msg "power_supply_health") :to-equal 0))
    (it "decodes empty sequences and empty strings"
      (expect (ros2-cdr-tests--get msg "cell_voltage") :to-equal nil)
      (expect (ros2-cdr-tests--get msg "location") :to-equal ""))))

(provide 'ros2-cdr-tests)
;;; ros2-cdr-tests.el ends here
