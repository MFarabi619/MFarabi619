;; Find `doom-dashboard-widget-banner` in the list and insert after it
(let ((pos (cl-position #'doom-dashboard-widget-banner +doom-dashboard-functions)))
  (when pos
    (setq +doom-dashboard-functions
          (append (cl-subseq +doom-dashboard-functions 0 (1+ pos))
                  (list (lambda ()
                          (insert "\"Do not proceed with a mess; messes just grow with time.\" ― Bjarne Stroustrup\n\n")))
                  (cl-subseq +doom-dashboard-functions (1+ pos))))))
