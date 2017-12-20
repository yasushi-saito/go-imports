;;; -*- lexical-binding: t -*-

(require 'thingatpt)

(defun go-imports-packages-path()
  "Returns the name of the file that checkpoints the package name list."
  (let ((gopath (car (split-string (getenv "GOPATH") ":" t))))
    (concat (file-name-as-directory gopath) ".go-imports-packages.el")))

(defvar go-imports-packages-hash (make-hash-table :test #'equal))

(defun go-imports-maybe-update-packages-list()
  (if (= (hash-table-count go-imports-packages-hash) 0)
      (with-temp-buffer
        (let ((packages-path (go-imports-packages-path)))
          (if (not (file-exists-p packages-path))
              (progn
                (go-imports-list-packages (getenv "GOROOT"))
                (mapc #'(lambda (root) (go-imports-list-packages root))
                      (split-string (getenv "GOPATH") ":" t))
                (write-region nil nil packages-path)))
          (insert-file-contents packages-path)
          (eval-buffer)
          ))))

(defun go-imports-reload-packages-list()
  "Reload package-name to package-path mappings by reading *.go
files under GOROOT and GOPATH."
  (interactive)
  (let ((packages-path (go-imports-packages-path)))
    (clrhash go-imports-packages-hash)
    (if (file-exists-p packages-path)
        (delete-file packages-path)))
  (go-imports-maybe-update-packages-list))

(defun go-imports-define-package(package path)
  "Internal function that defines a package-name to package-path mapping."
  (let ((v (gethash package go-imports-packages-hash)))
    (if (not (member path v))
        (puthash package (cons path v) go-imports-packages-hash))))

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
           (read-string "Package: " c 'go-imports-history))))
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
      (let ((path (ido-completing-read "Path: " paths)))
        (go-import-add nil path))))))

(defun go-imports-list-packages(root)
  (let ((perl-script "while (<>) {
  if (m!(.+)/[^/]+.go:package (\\S*)!) {
    my ($path, $package) = ($1, $2);
    next if ($package eq \"main\" or $package eq \"p\");
    if ($path =~ m!^\./!) { $path = substr($path,2); }
    $PACKAGES{$path} = $package;
  } else {
    # die \"Failed to parse line $_\";
  }
}
while(my($k, $v) = each %PACKAGES) {
  print \"(go-imports-define-package \\\"$v\\\" \\\"$k\\\")\n\"
}
"))
    (call-process "/bin/sh" nil t nil "-c"
                  (format "cd %s/src && find . -name *.go -a ! -name '*test.go' -a ! -path '*internal*' -a ! -path '*testdata*' | xargs grep -m1 ^package | perl -e '%s'"
                          root
                          perl-script))))

(provide 'go-imports)
