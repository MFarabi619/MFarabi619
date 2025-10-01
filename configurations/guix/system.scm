(use-modules (gnu))
(use-service-modules cups desktop networking ssh xorg)

(operating-system
  (locale "en_CA.utf8")
  (timezone "America/New_York")
  (keyboard-layout (keyboard-layout "us" #:options '("ctrl:nocaps")))
  (host-name "guix")

  (users (cons* (user-account
                  (name "mfarabi")
                  (comment "Mumtahin Farabi")
                  (group "users")
                  (home-directory "/home/mfarabi")
                  (supplementary-groups '("wheel" "netdev" "audio" "video")))
                %base-user-accounts))

  ;; Packages installed system-wide.  Users can also install packages
  ;; under their own account: use 'guix search KEYWORD' to search
  ;; for packages and 'guix install PACKAGE' to install a package.
  (packages
  (append
    (map specification->package
        '("emacs"
          "emacs-exwm"
          "emacs-vterm"
          "emacs-desktop-environment"
          "gcc"
          "cmake"
          "font-jetbrains-mono"
          ))
    %base-packages))

  ;; search available system services: 'guix system search KEYWORD'
  (services
   (append (list

                 ;; To configure OpenSSH, pass an 'openssh-configuration'
                 ;; record as a second argument to 'service' below.
                 (service openssh-service-type)
                 (service tor-service-type)
                 (service cups-service-type)
                 (set-xorg-configuration
                  (xorg-configuration (keyboard-layout keyboard-layout))))

           ;; default list of services we are appending to.
           %desktop-services))
  (bootloader (bootloader-configuration
                (bootloader grub-efi-bootloader)
                (targets (list "/boot/efi"))
                (keyboard-layout keyboard-layout)))
  (swap-devices (list (swap-space
                        (target (uuid
                                 "0b97a0c1-8028-450e-a101-b4cef73e29f8")))))

  ;; The list of file systems that get "mounted".  The unique
  ;; file system identifiers there ("UUIDs") can be obtained
  ;; by running 'blkid' in a terminal.
  (file-systems (cons* (file-system
                         (mount-point "/boot/efi")
                         (device (uuid "A04D-8D61"
                                       'fat32))
                         (type "vfat"))
                       (file-system
                         (mount-point "/")
                         (device (uuid
                                  "67368cae-7731-43dd-ae5a-f2123f163032"
                                  'ext4))
                         (type "ext4"))
                       (file-system
                         (mount-point "/home")
                         (device (uuid
                                  "ceed2cbc-8b6e-45e0-a0bb-9605747bd63a"
                                  'ext4))
                         (type "ext4")) %base-file-systems)))
