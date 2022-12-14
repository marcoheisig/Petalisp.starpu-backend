;;;; © 2016-2022 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.starpu-backend)

(defmethod backend-evaluator
    ((starpu-backend starpu-backend)
     (unknowns list)
     (lazy-arrays list))
  (funcall (evaluator-generator (length unknowns) (length lazy-arrays))
           (make-cstate starpu-backend unknowns lazy-arrays)))

(let ((cache (make-hash-table)))
  (defun evaluator-generator (number-of-arguments number-of-results)
    (alexandria:ensure-gethash
     number-of-arguments
     (alexandria:ensure-gethash number-of-results cache (make-hash-table))
     (let ((results (result-variables number-of-results))
           (arguments (argument-variables number-of-arguments)))
       (compile
        nil
        `(lambda (cstate)
           (lambda (,@results ,@arguments)
             (starpu:with-starpu-activity
               (with-starpu-data (cstate (,@results) (,@arguments))
                 (execute cstate))))))))))

(defun generate-variable (prefix integer)
  (intern
   (with-output-to-string (stream)
     (loop for char across (string prefix) do
       (write-char char stream))
     (format stream "~D" integer))
   #.*package*))

(defun result-variables (n)
  (loop for i below n collect (generate-variable "DST" i)))

(defun argument-variables (n)
  (loop for i below n collect (generate-variable "SRC" i)))

(defun execute (cstate)
  (with-accessors ((codelet-vector cstate-codelet-vector)
                   (program cstate-program)) cstate
    (petalisp.ir:do-program-kernels (kernel program)
      (starpu:task-insert
       (svref codelet-vector (petalisp.ir:kernel-number kernel))
       :data
       (let ((result '()))
         (do-kernel-outputs (buffer kernel)
           (push :w result)
           (push (buffer-starpu-data buffer) result))
         (do-kernel-inputs (buffer kernel)
           (push :r result)
           (push (buffer-starpu-data buffer) result))
         (nreverse result))
       :args
       (let ((result '()))
         ;; Pack the iteration space.
         (dolist (range (shape-ranges (kernel-iteration-space kernel)))
           (push :int64 result)
           (push (range-start range) result)
           (push :int64 result)
           (push (range-end range) result)
           (push :int64 result)
           (push (range-step range) result))
         ;; Pack strides and skips.
         (do-kernel-outputs (buffer kernel)
           (push :uint64 result)
           (push 0 result)
           (let* ((shape (buffer-shape buffer)))
             (loop for axis from 3 below (1- (shape-rank shape)) do
               (push :uint64 result)
               (push (range-size (shape-range shape axis)) result))))
         (do-kernel-inputs (buffer kernel)
           (push :uint64 result)
           (push 0 result)
           (let* ((shape (buffer-shape buffer)))
             (loop for axis from 3 below (1- (shape-rank shape)) do
               (push :uint64 result)
               (push (range-size (shape-range shape axis)) result))))
         ;; Pack all remaining coefficients.
         (do-kernel-store-instructions (store-instruction kernel)
           (let ((transformation (store-instruction-transformation store-instruction)))
             (loop for scaling across (transformation-scalings transformation)
                   for offset across (transformation-offsets transformation)
                   do (push :int64 result)
                      (push scaling result)
                      (push :int64 result)
                      (push offset result))))
         (do-kernel-stencils (stencil kernel)
           (loop for scaling across (stencil-scalings stencil)
                 for offset across (stencil-center stencil)
                 do (push :int64 result)
                    (push scaling result)
                    (push :int64 result)
                    (push offset result)))
         (do-kernel-instructions (instruction kernel)
           (when (iref-instruction-p instruction)
             (let ((transformation (iref-instruction-transformation instruction)))
               (push :int64 result)
               (push (elt (transformation-scalings transformation) 0) result)
               (push :int64 result)
               (push (elt (transformation-offsets transformation) 0) result))))
         (nreverse result))))
    (starpu:task-wait-for-all)))
