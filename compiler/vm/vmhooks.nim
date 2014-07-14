#
#
#           The Nimrod Compiler
#        (c) Copyright 2014 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements extension hooks for the VM.

import vmdef

type
  VmFrame* = object ## a frame object provides the interface between native
                    ## procs and interpreted procs.
    sf: PStackFrame # real underlying stack frame
    firstArg: int   # firstArg-1 is the position where 
                    # the result has to be stored

proc readLineWrapper(f: VmFrame) =
  let file = cast[TFile](f.getInt 0)
  f.setResultString file.readLine()

proc registerProc*(c: VmContext; fullname: string; procedure: VmCallback) =
  let c = PCtx(c)
  let comps = fullname.split('.')
  # put the last component of the name into c.marker to speed up lookups:
  
vm.registerProc "stdlib.system.readLine", readLineWrapper

