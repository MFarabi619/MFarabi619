;; -*- lexical-binding: t; -*-

(evil-mode 1)
(tab-bar-mode 1)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(centaur-tabs-mode t)
(display-time-mode 1)
(doom-modeline-mode 1)
(display-battery-mode 1)
(pixel-scroll-precision-mode 1)
(global-display-line-numbers-mode 1)

(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)
(add-hook 'doom-modeline-mode-hook #'nyan-mode)
(define-key evil-normal-state-map (kbd "j") 'evil-next-visual-line)
(define-key evil-normal-state-map (kbd "k") 'evil-previous-visual-line)
(global-set-key (kbd "<f8>") #'dirvish-side)

(setq inhibit-startup-screen nil
      inhibit-startup-buffer-menu nil
      initial-buffer-choice 'fancy-startup
      display-line-numbers-type 'relative
      display-time-day-and-date t
      doom-theme 'doom-gruvbox
      doom-modeline-hud t
      doom-modeline-persp-name t
      doom-modeline-major-mode-icon t
      evil-ex-substitute-global t
      evil-escape-key-sequence "jk"
      centaur-tabs-gray-out-icons t
      centaur-tabs-show-count t
      centaur-tabs-enable-key-bindings t
      centaur-tabs-show-navigation-buttons t
      user-full-name "Mumtahin Farabi"
      user-mail-address "mfarabi619@gmail.com")

(use-package nyan-mode
  :ensure t
  :config
  (setq nyan-animate-nyancat t
        nyan-wavy-trail t))

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

