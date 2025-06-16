;; -*- lexical-binding: t; -*-

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

(setq inhibit-startup-screen nil
      inhibit-startup-buffer-menu nil
      initial-buffer-choice 'fancy-startup)

(tab-bar-mode 1)
(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

(display-battery-mode 1)
(display-time-mode 1)
(setq display-time-day-and-date t)

(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)
(pixel-scroll-precision-mode 1)
(setq doom-theme 'doom-gruvbox)

(doom-modeline-mode 1)
(setq doom-modeline-hud t)
(setq doom-modeline-persp-name t)
(setq doom-modeline-major-mode-icon t)

(use-package nyan-mode
  :ensure t
  :config
  (setq nyan-animate-nyancat t
        nyan-wavy-trail t))

(add-hook 'doom-modeline-mode-hook #'nyan-mode)

(evil-mode 1)
(setq evil-ex-substitute-global t
      evil-escape-key-sequence "jk")
(define-key evil-normal-state-map (kbd "j") 'evil-next-visual-line)
(define-key evil-normal-state-map (kbd "k") 'evil-previous-visual-line)


(centaur-tabs-mode t)
(setq centaur-tabs-gray-out-icons t)
(setq centaur-tabs-show-count t)
(setq centaur-tabs-enable-key-bindings t)
(setq centaur-tabs-show-navigation-buttons t)

(use-package dirvish
  :ensure t
  :config
  (dirvish-override-dired-mode)
  (setq dirvish-preview-dispatchers
        (cl-substitute 'pdf-tools 'pdf dirvish-preview-dispatchers))
  (dirvish-define-preview eza (file)
    "Use `eza' to generate directory preview."
    :require ("eza") ; Ensure eza executable exists
    (when (file-directory-p file)
      `(shell . ("eza" "-al" "--color=always" "--icons=always"
                 "--group-directories-first" ,file))))
  (push 'eza dirvish-preview-dispatchers)
  (setq dirvish-side t
        (setq dirvish-side-display-alist '((side . right) (slot . -1)))
        (setq dirvish-peek-mode t)
        (setq dirvish-side-auto-close t)
        (setq dirvish-side-follow-mode t)
        (add-hook 'emacs-startup-hook #'dirvish-side))

  (global-set-key (kbd "<f8>") #'dirvish-side)

  (setq user-full-name "Mumtahin Farabi"
        user-mail-address "mfarabi619@gmail.com")
