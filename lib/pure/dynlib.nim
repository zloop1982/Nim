#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements the ability to access symbols from shared
## libraries. On POSIX this uses the ``dlsym`` mechanism, on
## Windows ``LoadLibrary``.

import strutils

type
  LibHandle* = pointer ## a handle to a dynamically loaded library

{.deprecated: [TLibHandle: LibHandle].}

proc loadLib*(path: string, global_symbols=false): LibHandle {.gcsafe.}
  ## loads a library from `path`. Returns nil if the library could not
  ## be loaded.

proc loadLib*(): LibHandle {.gcsafe.}
  ## gets the handle from the current executable. Returns nil if the
  ## library could not be loaded.

proc unloadLib*(lib: LibHandle) {.gcsafe.}
  ## unloads the library `lib`

proc raiseInvalidLibrary*(name: cstring) {.noinline, noreturn.} =
  ## raises an `EInvalidLibrary` exception.
  var e: ref LibraryError
  new(e)
  e.msg = "could not find symbol: " & $name
  raise e

proc symAddr*(lib: LibHandle, name: cstring): pointer {.gcsafe.}
  ## retrieves the address of a procedure/variable from `lib`. Returns nil
  ## if the symbol could not be found.

proc checkedSymAddr*(lib: LibHandle, name: cstring): pointer =
  ## retrieves the address of a procedure/variable from `lib`. Raises
  ## `EInvalidLibrary` if the symbol could not be found.
  result = symAddr(lib, name)
  if result == nil: raiseInvalidLibrary(name)

proc libCandidates*(s: string, dest: var seq[string]) =
  ## given a library name pattern `s` write possible library names to `dest`.
  var le = strutils.find(s, '(')
  var ri = strutils.find(s, ')', le+1)
  if le >= 0 and ri > le:
    var prefix = substr(s, 0, le - 1)
    var suffix = substr(s, ri + 1)
    for middle in split(substr(s, le + 1, ri - 1), '|'):
      libCandidates(prefix & middle & suffix, dest)
  else:
    add(dest, s)

proc loadLibPattern*(pattern: string, global_symbols=false): LibHandle =
  ## loads a library with name matching `pattern`, similar to what `dlimport`
  ## pragma does. Returns nil if the library could not be loaded.
  ## Warning: this proc uses the GC and so cannot be used to load the GC.
  var candidates = newSeq[string]()
  libCandidates(pattern, candidates)
  for c in candidates:
    result = loadLib(c, global_symbols)
    if not result.isNil: break

when defined(posix):
  #
  # =========================================================================
  # This is an implementation based on the dlfcn interface.
  # The dlfcn interface is available in Linux, SunOS, Solaris, IRIX, FreeBSD,
  # NetBSD, AIX 4.2, HPUX 11, and probably most other Unix flavors, at least
  # as an emulation layer on top of native functions.
  # =========================================================================
  #
  var
    RTLD_NOW {.importc: "RTLD_NOW", header: "<dlfcn.h>".}: int
    RTLD_GLOBAL {.importc: "RTLD_GLOBAL", header: "<dlfcn.h>".}: int

  proc dlclose(lib: LibHandle) {.importc, header: "<dlfcn.h>".}
  proc dlopen(path: cstring, mode: int): LibHandle {.
      importc, header: "<dlfcn.h>".}
  proc dlsym(lib: LibHandle, name: cstring): pointer {.
      importc, header: "<dlfcn.h>".}

  proc loadLib(path: string, global_symbols=false): LibHandle =
    var flags = RTLD_NOW
    if global_symbols: flags = flags or RTLD_GLOBAL
    return dlopen(path, flags)
  proc loadLib(): LibHandle = return dlopen(nil, RTLD_NOW)
  proc unloadLib(lib: LibHandle) = dlclose(lib)
  proc symAddr(lib: LibHandle, name: cstring): pointer =
    return dlsym(lib, name)

elif defined(windows) or defined(dos):
  #
  # =======================================================================
  # Native Windows Implementation
  # =======================================================================
  #
  when defined(cpp):
    type
      THINSTANCE {.importc: "HINSTANCE".} = object
        x: pointer
  else:
    type
      THINSTANCE {.importc: "HINSTANCE".} = pointer

  proc FreeLibrary(lib: THINSTANCE) {.importc, header: "<windows.h>", stdcall.}
  proc winLoadLibrary(path: cstring): THINSTANCE {.
      importc: "LoadLibraryA", header: "<windows.h>", stdcall.}
  proc getProcAddress(lib: THINSTANCE, name: cstring): pointer {.
      importc: "GetProcAddress", header: "<windows.h>", stdcall.}

  proc loadLib(path: string, global_symbols=false): LibHandle =
    result = cast[LibHandle](winLoadLibrary(path))
  proc loadLib(): LibHandle =
    result = cast[LibHandle](winLoadLibrary(nil))
  proc unloadLib(lib: LibHandle) = FreeLibrary(cast[THINSTANCE](lib))

  proc symAddr(lib: LibHandle, name: cstring): pointer =
    result = getProcAddress(cast[THINSTANCE](lib), name)

else:
  {.error: "no implementation for dynlib".}
