;;; ox-leanpub.el --- Leanpub Markdown Back-End for Org Export Engine

;; Author: Juan Reyero <juan _at! juanreyero.com>
;; Keywords: org, wp, markdown, leanpub

;;; Commentary:

;;; Small adaptation of ox-md.el to make the exported markdown work
;;; better for Leanpub (http://leanpub.com) publication.  It handles
;;; footnotes, and makes source code separated from its output, and
;;; the output does not display line numbers.  Html blocks are
;;; ignored.

;;; Missing:

;;; - Tables should appear just as they are in org-mode.  Currently
;;;   they are ignored.
;;; - When using IDs for cross linking they should be taken advantage
;;;   of.  Leanpub's markdown is supposed to be able to crosslink with
;;;   ids.

;;; Code:

(eval-when-compile (require 'cl))
(require 'ox-md)

;;; Define Back-End

(org-export-define-derived-backend 'leanpub 'md
  :export-block '("leanpub" "LEANPUB")
  :menu-entry
  '(?L "Export to Leanpub Markdown"
       ((?L "To temporary buffer"
	    (lambda (a s v b) (org-leanpub-export-as-markdown a s v)))
	(?l "To file" (lambda (a s v b) (org-leanpub-export-to-markdown a s v)))
	(?o "To file and open"
	    (lambda (a s v b)
	      (if a (org-leanpub-export-to-markdown t s v)
		(org-open-file (org-leanpub-export-to-markdown nil s v)))))))
  :translate-alist '((fixed-width . org-leanpub-fixed-width-block)
                     (example-block . org-leanpub-fixed-width-block)
                     (src-block . org-leanpub-src-block)
                     (plain-text . org-leanpub-plain-text)
                     (inner-template . org-leanpub-inner-template)
                     (footnote-reference . org-leanpub-footnote-reference)
                     (headline . org-leanpub-headline)
                     (link . org-leanpub-link)
                     (latex-fragment . org-leanpub-latex-fragment)
                     (table . org-leanpub-ignore)
                     ;; Will not work with leanpub:
                     (export-block . org-leanpub-ignore))) ; #+html


(defun org-leanpub-latex-fragment (latex-fragment contents info)
  "Transcode a LATEX-FRAGMENT object from Org to Markdown.
CONTENTS is nil.  INFO is a plist holding contextual information."
  (format "{$$}%s{/$$}"
          ;; Need to figure out the right regular expression.  Got
          ;; lost in the escaping.
          (replace-regexp-in-string
           (regexp-quote "\\[") ""
           (replace-regexp-in-string
            (regexp-quote "\\]") ""
            (org-element-property :value latex-fragment)))))

;;; Adding the id, hoping to make crosslinks work at some point.
;;; So far it is useless.
(defun org-leanpub-headline (headline contents info)
  (concat (let ((id (org-element-property :ID headline)))
            (if id
                (format "{#%s}\n" id)
              ""))
          (org-md-headline headline contents info)))

;;; Required to make footnotes work.
(defun org-leanpub-inner-template (contents info)
  "Return complete document string after markdown conversion.
CONTENTS is the transcoded contents string.  INFO is a plist
holding export options."
  (concat
   contents
   (let ((definitions (org-export-collect-footnote-definitions
                       (plist-get info :parse-tree) info)))
     (mapconcat (lambda (ref)
                  (let ((id (format "[^%s]: " (let ((label (cadr ref)))
                                                (if label
                                                    label
                                                  (car ref))))))
                    (let ((def (nth 2 ref)))
                      (concat id (org-export-data def info)))))
                definitions "\n\n"))))

(defun org-leanpub-footnote-reference (footnote contents info)
  (format "[^%s]"
          (let ((label (org-element-property :label footnote)))
            (if label
                label
              (org-export-get-footnote-number footnote info)))))

(defun org-leanpub-ignore (src-block contents info)
  "")

(defun org-leanpub-plain-text (text info)
  text)

;;; {lang="python"}
;;; ~~~~~~~~
;;; def longitude_circle(diameter):
;;;     return math.pi * diameter
;;; longitude(10)
;;; ~~~~~~~~
(defun org-leanpub-src-block (src-block contents info)
  "Transcode SRC-BLOCK element into Markdown format.
CONTENTS is nil.  INFO is a plist used as a communication
channel."
  (let ((lang (org-element-property :language src-block)))
    (format "{lang=\"%s\"}\n~~~~~~~~\n%s~~~~~~~~"
            lang
            (org-remove-indentation
             (org-element-property :value src-block)))))

;;; A> {linenos=off}
;;; A> ~~~~~~~~
;;; A> 123.0
;;; A> ~~~~~~~~
(defun org-leanpub-fixed-width-block (src-block contents info)
  "Transcode FIXED-WIDTH-BLOCK element into Markdown format.
CONTENTS is nil.  INFO is a plist used as a communication
channel."
  (replace-regexp-in-string
   "^" "A> "
   (format "{linenos=off}\n~~~~~~~~\n%s~~~~~~~~"
           (org-remove-indentation
            (org-element-property :value src-block)))))

(defun org-leanpub-link (link contents info)
  "Transcode LINE-BREAK object into Markdown format.
CONTENTS is the link's description.  INFO is a plist used as
a communication channel."
  (let ((type (org-element-property :type link)))
    (cond ((member type '("custom-id" "id"))
           (let ((id (org-element-property :path link)))
             (format "[%s](#%s)" contents id)))
          ((org-export-inline-image-p link org-html-inline-image-rules)
           (let ((path (let ((raw-path (org-element-property :path link)))
                         (if (not (file-name-absolute-p raw-path)) raw-path
                           (expand-file-name raw-path)))))
             (format "![%s](%s)"
                     (let ((caption (org-export-get-caption
                                     (org-export-get-parent-element link))))
                       (if caption
                           (org-export-data caption info)
                         ""))
                     path)))
          (t (let* ((raw-path (org-element-property :path link))
                    (path (if (member type '("http" "https" "ftp"))
                              (concat type ":" raw-path)
                            nil)))
               (if path
                   (if (not contents) (format "<%s>" path)
                     (format "[%s](%s)" contents path))
                 ""))))))

;;; Interactive function

;;;###autoload
(defun org-leanpub-export-as-markdown (&optional async subtreep visible-only)
  "Export current buffer to a Markdown buffer.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

Export is done in a buffer named \"*Org MD Export*\", which will
be displayed when `org-export-show-temporary-export-buffer' is
non-nil."
  (interactive)
  (org-export-to-buffer 'leanpub "*Org LEANPUB Export*"
    async subtreep visible-only nil nil (lambda () (text-mode))))

;;;###autoload
(defun org-leanpub-export-to-markdown (&optional async subtreep visible-only)
  "Export current buffer to a Markdown file.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

Return output file's name."
  (interactive)
  (let ((outfile (org-export-output-file-name ".md" subtreep)))
    (org-export-to-file 'leanpub outfile async subtreep visible-only)))

(provide 'ox-leanpub)

;;; ox-leanpub.el ends here
