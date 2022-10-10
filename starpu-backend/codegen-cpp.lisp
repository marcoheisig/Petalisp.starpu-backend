;;;; © 2016-2022 Marco Heisig         - license: GNU AGPLv3 -*- coding: utf-8 -*-

(in-package #:petalisp.starpu-backend)

(defun write-blueprint-cpp (name stream)
  (when *emit-verbose-code*
    (format stream "#include <stdio.h>~%"))
  (format stream "#include <math.h>~%")
  (format stream "#include <starpu.h>~%")
  (format stream "extern \"C\" {~%")
  (format stream "void ~A (void *buffers[], void *args) {~%" name)
  (write-prologue name stream)
  ;; Loop over the iteration space.
  (loop for axis from 0 for range-info in *iteration-space-info* do
    (ecase range-info
      (:contiguous
       (format stream "  for (int64_t i~D = start~D; i~D < end~D; i~D += 1)~%"
               axis axis axis axis axis))
      (:strided
       (format stream "  for (int64_t i~D = start~D; i~D < end~D; i~D += step~D)~%"
               axis axis axis axis axis axis))))
  ;; Print the body.
  (write-instructions stream)
  (write-epilogue name stream)
  (format stream "}~%")
  (format stream "}~%"))
