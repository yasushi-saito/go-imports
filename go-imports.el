;;; go-imports.el --- Insert go import statement given package name
;;
;; Author: Yaz Saito
;; URL: https://github.com/yasushi-saito/go-imports
;; Keywords: tools, go, import
;; Version: 20171219.1
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Commentary:
;;
;; Add something like below to `~/.emacs`:
;;
;; (add-hook 'go-mode-hook
;;           #'(lambda()
;;               (require 'go-imports)
;; 	          (define-key go-mode-map "\C-cI" 'go-imports-insert-import)
;; 	          (define-key go-mode-map "\C-cR" go-imports-reload-packages-list)))
;;
;; Say you have github.com/stretchr/testify/require in your GOPATH, and you want
;; to use this package in your go file.  Invoking
;;
;; (go-imports-insert-import "require")
;;
;; will insert the import line
;;
;; import (
;;   "github.com/stretchr/testify/require"
;; )
;;
;; in the file.  If invoked interactively, it will insert an import for the
;; symbol at point.
;;
;; The mappings from the package name (e.g., "require") to thus package path
;; (e.g., "github.com/stretchr/testify/require") is discovered by scanning all
;; the *.go files under GOROOT and GOPATH when the go-imports-insert-import is
;; first called.
;;
;; Calling go-imports-reload-packages-list will reload the package-name
;; mappings.

(require 'thingatpt)

;;; Code:

(defun go-imports-packages-path()
  "Returns the name of the file that checkpoints the package name list."
  (let ((gopath (car (split-string (getenv "GOPATH") ":" t))))
    (concat (file-name-as-directory gopath) ".go-imports-packages.el")))

(defvar go-imports-packages-hash (make-hash-table :test #'equal)
  "Hash table that maps a package path (e.g., \"html/template\")
to its package name (e.g., \"template\").")

(defvar go-imports-packages-list nil
  "List of package names.")

(defvar go-imports-perl-script
  "use warnings;
use strict;
sub go_package_name {
    my ($path) = @_;
    unless (open(IN, $path)) {
        warn \"open $: $.\";
        return ''
    }
    my $package;
    while (<IN>) {
        if (/^package (\\S+)/) {
            $package = $1;
            last
        }
    }
    close(IN);
    return $package;
}
sub has_prefix {
    my ($str, $prefix) = @_;
    return (substr($str, 0, length($prefix)) eq $prefix);
}
sub visit_dir {
    my ($dir, $packages, $visited) = @_;
    my ($dev, $ino) = stat($dir);
    my ($dev_ino) = \"$dev/$ino\";
    if (defined $visited->{$dev_ino}) {
        return
    }
    $visited->{$dev_ino} = 1;
    unless (opendir(DIR, $dir)) {
        warn \"opendir $dir: $.\\n\";
        return
    }
    my @filenames = readdir(DIR);
    closedir(DIR);
    my $package = '';
    foreach my $filename (@filenames) {
        if (has_prefix($filename, \".\") or has_prefix($filename, \"bazel-\")) {
            next;
        }
        my $path = \"$dir/$filename\";
        if (-d $path) {
            visit_dir($path, $packages, $visited);
            next
        }
        if ($path !~ /\\.go$/) {
            next
        }
        my $p = go_package_name($path);
        if ($p !~ /test$/ and $p ne '') {
            $package = $p;
            last
        }
    }
    if ($package ne '' and $package ne 'main' and $package ne 'p') {
        $packages->{$dir} = $package;
    }
}
warn \"ARGV: @ARGV\\n\";
for my $root (@ARGV) {
    my ($packages, $visited) = ({}, {});
    visit_dir(\"$root/src\", $packages, $visited);
    while (my($dir, $name) = each %$packages) {
        my $path = $dir;
        if ($dir =~ m!/vendor/(.*)!) {
            $path = $1;
        } else {
            for my $root (@ARGV) {
                my $root_prefix = \"$root/src/\";
                if (has_prefix($dir, $root_prefix)) {
                    $path = substr($dir, length($root_prefix));
                    last
                }
            }
        }
        print \"(go-imports-define-package \\\"$name\\\" \\\"$path\\\")\\n\"
    }
}
"
  "A perl script that finds package definitions in *.go files under the given directories")

(defun go-imports-maybe-update-packages-list()
  (if (= (hash-table-count go-imports-packages-hash) 0)
      (with-temp-buffer
        (setq go-imports-packages-list nil)
        (let ((packages-path (go-imports-packages-path)))
          (if (not (file-exists-p packages-path))
              (go-imports-list-packages
               packages-path
               (cons (getenv "GOROOT") (split-string (getenv "GOPATH") ":" t))))
          (insert-file-contents packages-path)
          (eval-buffer)
          ))))

(defun go-imports-define-package(package path)
  "Internal function that defines a package-name to package-path mapping."
  (let ((v (gethash package go-imports-packages-hash)))
    (when (not (member path v))
      (puthash package (cons path v) go-imports-packages-hash)
      (add-to-list 'go-imports-packages-list package)
      )))

;;;###autoload
(defun go-imports-reload-packages-list()
  "Reload package-name to package-path mappings by reading *.go
files under GOROOT and GOPATH."
  (interactive)
  (let ((packages-path (go-imports-packages-path)))
    (clrhash go-imports-packages-hash)
    (if (file-exists-p packages-path)
        (delete-file packages-path)))
  (go-imports-maybe-update-packages-list))

;;;###autoload
(defun go-imports-insert-import(package)
  "Insert go import statement for PACKAGE. For example, if
PACKAGE is \"ioutil\", then line \"io/ioutil\" will be inserted
in the import block in the file.

When this function is called for the first time, it will
initialize the mappings from package names (\"ioutil\") to the
package path (\"io/ioutil\") by listing all the *.go files under
directories named in GOROOT and GOPATH environment variables. The
mapping is checkpointed in DIR/.go-imports-packages.el, where DIR
is the first directory in GOPATH.

The package-name mappings are *not* automatically updated as *.go
files are modified.  Call go-imports-reload-packages-list to
reload the mappings."
  (interactive
   (list (let ((c (thing-at-point 'word)))
           (ido-completing-read "Package: " go-imports-packages-list
                                nil t nil 'go-imports-package-history))))
  (go-imports-maybe-update-packages-list)
  (let ((paths (gethash ;(prin1-to-string package)
                package
                go-imports-packages-hash)))
    (cond
     ((null paths)
      (error "Package '%s' not found" package))
     ((= (length paths) 1)
      (go-import-add nil (car paths)))
     (t
      (let ((path (ido-completing-read "Path: " paths
                                       nil nil nil 'go-imports-path-history)))
        (go-import-add nil path))))))

(defun go-imports-list-packages(packages-file root-dirs)
  "Discover *.go files under ROOT-DIRS and produce a list of
go-imports-define-package statements in PACKAGES-FILE.  ROOT-DIRS
is a list of directory names. Existing contents of PACKAGES-FILE
are overwritten."
  (let* ((tmp-perl-file (concat (make-temp-file "go-imports") ".pl")))
    (unwind-protect
        (progn
          (with-temp-file tmp-perl-file
            (insert go-imports-perl-script))
          (apply #'call-process
                 "perl" nil `((:file ,packages-file) ,(concat packages-file "-errors")) nil
                 tmp-perl-file (remove nil root-dirs)))
      (delete-file tmp-perl-file))))

(provide 'go-imports)

;;; -*- lexical-binding: t -*-
;;; go-imports.el ends here
