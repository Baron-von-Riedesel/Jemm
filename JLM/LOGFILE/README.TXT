
  LOGFILE hooks int 41h and redirects all output of int 41h, ax=0000,
 to a 8 MB buffer in a XMS memory block.

  It's meant to be used with a debug version of Jemm. To write the buffer
 to a file, a helper 16-bit app is required.

  LOGFILE is useful if a graphics mode is set - then Jemm's standard
 int 41h handler is unable to display anything.
