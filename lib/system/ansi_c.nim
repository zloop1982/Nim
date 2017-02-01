#
#
#            Nim's Runtime Library
#        (c) Copyright 2013 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This include file contains headers of Ansi C procs
# and definitions of Ansi C types in Nim syntax
# All symbols are prefixed with 'c_' to avoid ambiguities

{.push hints:off}

proc c_memchr(s: pointer, c: cint, n: csize): pointer {.
  importc: "memchr", header: "<string.h>".}
proc c_memcmp(a, b: pointer, size: csize): cint {.
  importc: "memcmp", header: "<string.h>", noSideEffect.}
proc c_memcpy(a, b: pointer, size: csize): pointer {.
  importc: "memcpy", header: "<string.h>", discardable.}
proc c_memmove(a, b: pointer, size: csize): pointer {.
  importc: "memmove", header: "<string.h>",discardable.}
proc c_memset(p: pointer, value: cint, size: csize): pointer {.
  importc: "memset", header: "<string.h>", discardable.}
proc c_strcmp(a, b: cstring): cint {.
  importc: "strcmp", header: "<string.h>", noSideEffect.}

type
  C_JmpBuf {.importc: "jmp_buf", header: "<setjmp.h>".} = object

when defined(windows):
  const
    SIGABRT = cint(22)
    SIGFPE = cint(8)
    SIGILL = cint(4)
    SIGINT = cint(2)
    SIGSEGV = cint(11)
    SIGTERM = cint(15)
elif defined(macosx) or defined(linux) or defined(freebsd) or
     defined(openbsd) or defined(netbsd) or defined(solaris):
  const
    SIGABRT = cint(6)
    SIGFPE = cint(8)
    SIGILL = cint(4)
    SIGINT = cint(2)
    SIGSEGV = cint(11)
    SIGTERM = cint(15)
    SIGPIPE = cint(13)
else:
  when NoFakeVars:
    {.error: "SIGABRT not ported to your platform".}
  else:
    var
      SIGINT {.importc: "SIGINT", nodecl.}: cint
      SIGSEGV {.importc: "SIGSEGV", nodecl.}: cint
      SIGABRT {.importc: "SIGABRT", nodecl.}: cint
      SIGFPE {.importc: "SIGFPE", nodecl.}: cint
      SIGILL {.importc: "SIGILL", nodecl.}: cint
    when defined(macosx) or defined(linux):
      var SIGPIPE {.importc: "SIGPIPE", nodecl.}: cint

when defined(macosx):
  const SIGBUS = cint(10)
else:
  template SIGBUS: untyped = SIGSEGV

when defined(nimSigSetjmp) and not defined(nimStdSetjmp):
  proc c_longjmp(jmpb: C_JmpBuf, retval: cint) {.
    header: "<setjmp.h>", importc: "siglongjmp".}
  template c_setjmp(jmpb: C_JmpBuf): cint =
    proc c_sigsetjmp(jmpb: C_JmpBuf, savemask: cint): cint {.
      header: "<setjmp.h>", importc: "sigsetjmp".}
    c_sigsetjmp(jmpb, 0)
elif defined(nimRawSetjmp) and not defined(nimStdSetjmp):
  proc c_longjmp(jmpb: C_JmpBuf, retval: cint) {.
    header: "<setjmp.h>", importc: "_longjmp".}
  proc c_setjmp(jmpb: C_JmpBuf): cint {.
    header: "<setjmp.h>", importc: "_setjmp".}
else:
  proc c_longjmp(jmpb: C_JmpBuf, retval: cint) {.
    header: "<setjmp.h>", importc: "longjmp".}
  proc c_setjmp(jmpb: C_JmpBuf): cint {.
    header: "<setjmp.h>", importc: "setjmp".}

type c_sighandler_t = proc (a: cint) {.noconv.}
proc c_signal(sign: cint, handler: proc (a: cint) {.noconv.}): c_sighandler_t {.
  importc: "signal", header: "<signal.h>", discardable.}

proc c_fprintf(f: File, frmt: cstring): cint {.
  importc: "fprintf", header: "<stdio.h>", varargs, discardable.}
proc c_printf(frmt: cstring): cint {.
  importc: "printf", header: "<stdio.h>", varargs, discardable.}

proc c_sprintf(buf, frmt: cstring): cint {.
  importc: "sprintf", header: "<stdio.h>", varargs, noSideEffect.}
  # we use it only in a way that cannot lead to security issues

proc c_fileno(f: File): cint {.
  importc: "fileno", header: "<fcntl.h>".}

proc c_malloc(size: csize): pointer {.
  importc: "malloc", header: "<stdlib.h>".}
proc c_free(p: pointer) {.
  importc: "free", header: "<stdlib.h>".}
proc c_realloc(p: pointer, newsize: csize): pointer {.
  importc: "realloc", header: "<stdlib.h>".}

{.pop}
