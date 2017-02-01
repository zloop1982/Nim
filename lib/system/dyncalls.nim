#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This file implements the ability to call native procs from libraries.
# It is not possible to do this in a platform independent way, unfortunately.
# However, the interface has been designed to take platform differences into
# account and been ported to all major platforms.

{.push stack_trace: off.}

const
  NilLibHandle: LibHandle = nil

proc rawWrite(f: File, s: string) =
  # we cannot throw an exception here!
  discard writeBuffer(f, cstring(s), s.len)

proc nimLoadLibraryError(path: string) =
  # carefully written to avoid memory allocation:
  stderr.rawWrite("could not load: ")
  stderr.rawWrite(path)
  stderr.rawWrite("\n")
  when not(defined(nimDebugDlOpen)):
    stderr.rawWrite("compile with -d:nimDebugDlOpen for more information\n")
  quit(1)

proc procAddrError(name: cstring) {.noinline.} =
  # carefully written to avoid memory allocation:
  stderr.rawWrite("could not import: ")
  stderr.write(name)
  stderr.rawWrite("\n")
  quit(1)

# this code was inspired from Lua's source code:
# Lua - An Extensible Extension Language
# Tecgraf: Computer Graphics Technology Group, PUC-Rio, Brazil
# http://www.lua.org
# mailto:info@lua.org

when defined(posix):
  #
  # =========================================================================
  # This is an implementation based on the dlfcn interface.
  # The dlfcn interface is available in Linux, SunOS, Solaris, IRIX, FreeBSD,
  # NetBSD, AIX 4.2, HPUX 11, and probably most other Unix flavors, at least
  # as an emulation layer on top of native functions.
  # =========================================================================
  #

  # c stuff:
  when defined(linux) or defined(macosx):
    const RTLD_NOW = cint(2)
  else:
    var
      RTLD_NOW {.importc: "RTLD_NOW", header: "<dlfcn.h>".}: cint

  proc dlclose(lib: LibHandle) {.importc, header: "<dlfcn.h>".}
  proc dlopen(path: cstring, mode: cint): LibHandle {.
      importc, header: "<dlfcn.h>".}
  proc dlsym(lib: LibHandle, name: cstring): ProcAddr {.
      importc, header: "<dlfcn.h>".}

  proc dlerror(): cstring {.importc, header: "<dlfcn.h>".}

  proc nimUnloadLibrary(lib: LibHandle) =
    dlclose(lib)

  proc nimLoadLibrary(path: string): LibHandle =
    result = dlopen(path, RTLD_NOW)
    when defined(nimDebugDlOpen):
      let error = dlerror()
      if error != nil:
        stderr.write(error)
        stderr.rawWrite("\n")

  proc nimGetProcAddr(lib: LibHandle, name: cstring): ProcAddr =
    result = dlsym(lib, name)
    if result == nil: procAddrError(name)

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
    proc getProcAddress(lib: THINSTANCE, name: cstring): ProcAddr {.
        importcpp: "(void*)GetProcAddress(@)", header: "<windows.h>", stdcall.}
  else:
    type
      THINSTANCE {.importc: "HINSTANCE".} = pointer
    proc getProcAddress(lib: THINSTANCE, name: cstring): ProcAddr {.
        importc: "GetProcAddress", header: "<windows.h>", stdcall.}

  proc freeLibrary(lib: THINSTANCE) {.
      importc: "FreeLibrary", header: "<windows.h>", stdcall.}
  proc winLoadLibrary(path: cstring): THINSTANCE {.
      importc: "LoadLibraryA", header: "<windows.h>", stdcall.}

  proc nimUnloadLibrary(lib: LibHandle) =
    freeLibrary(cast[THINSTANCE](lib))

  proc nimLoadLibrary(path: string): LibHandle =
    result = cast[LibHandle](winLoadLibrary(path))

  proc nimGetProcAddr(lib: LibHandle, name: cstring): ProcAddr =
    result = getProcAddress(cast[THINSTANCE](lib), name)
    if result != nil: return
    const decorated_length = 250
    var decorated: array[decorated_length, char]
    decorated[0] = '_'
    var m = 1
    while m < (decorated_length - 5):
      if name[m - 1] == '\x00': break
      decorated[m] = name[m - 1]
      inc(m)
    decorated[m] = '@'
    for i in countup(0, 50):
      var k = i * 4
      if k div 100 == 0: 
        if k div 10 == 0:
          m = m + 1
        else:
          m = m + 2
      else:
        m = m + 3
      decorated[m + 1] = '\x00'
      while true:
        decorated[m] = chr(ord('0') + (k %% 10))
        dec(m)
        k = k div 10
        if k == 0: break
      result = getProcAddress(cast[THINSTANCE](lib), decorated)
      if result != nil: return
    procAddrError(name)

else:
  {.error: "no implementation for dyncalls".}

{.pop.}
