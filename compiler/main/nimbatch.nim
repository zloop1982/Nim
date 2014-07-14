#
#
#           The Nimrod Compiler
#        (c) Copyright 2014 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This file implements the new "batch compiler" that can translate Nimrod
# code into POSIX shell scripts or Windows ``.bat`` files. Only a small
# subset of Nimrod can be translated. This compiler also acts as a new
# "hacking the Nimrod compiler" tutorial.


## ==============================
## Let's hack the Nimrod compiler
## ==============================

## Starting with version 0.9.6 the compiler's internals have been cleaned up
## quite a bit. However, still lot's of weird modules need to be imported
## before we can start:

import
  llstream, strutils, ast, astalgo, lexer, syntaxes, renderer, options, msgs,
  os, condsyms, rodread, rodwrite, times,
  wordrecg, sem, semdata, idents, passes, docgen, extccomp,
  cgen, jsgen, json, nversion,
  platform, nimconf, importer, passaux, depends, vm, vmdef, types, idgen,
  tables, docgen2, service, parser, modules

proc `=~`(s: PSym; name: string): bool =
  let a = name.split('.')
  var s = s
  for i in countdown(a.high, a.low):
    if s == nil or not identEq(s.name, a[i]): return false
    s = s.owner
  return true

type
  ShellTarget = enum
    targetBatch, targetSh
  Context = ref object
    target: ShellTarget
    code: string

proc `=~`(n: PNode; name: string): bool =
  result = n.kind == nkSym and match(n.sym, name)

proc gen(c: Context; n: PNode) =
  template `~`(x): expr = op =~ x
  template `|`(a, b): expr = (if c.target == targetBatch: a else: b)
  template add(x) = c.code.add(x)
  template addf(x, y) = c.code.addf(x, y)

  case n.kind
  of nkIfStmt, nkIfExpr:

  of nkForStmt:
    
  of nkCallKinds:
    let op = n[0]
    if ~"stdlib.os.changeDir":
      addf("" | "", 
    elif ~"stdlib.os.createDir":
      addf("mkdir $#", 

proc semanticPasses() =
  registerPass verbosePass
  registerPass semPass

proc commandCompileToSH =
  #incl(gGlobalOptions, optSafeCode)
  setTarget(osJS, cpuJS)
  #initDefines()
  defineSymbol("nimrod") # 'nimrod' is always defined
  defineSymbol("batch")
  semanticPasses()
  registerPass(JSgenPass)
  compileProject()

proc wantMainModule =
  if gProjectFull.len == 0:
    if optMainModule.len == 0:
      fatal(gCmdLineInfo, errCommandExpectsFilename)
    else:
      gProjectName = optMainModule
      gProjectFull = gProjectPath / gProjectName

  gProjectMainIdx = addFileExt(gProjectFull, NimExt).fileInfoIdx

proc requireMainModuleOption =
  if optMainModule.len == 0:
    fatal(gCmdLineInfo, errMainModuleMustBeSpecified)
  else:
    gProjectName = optMainModule
    gProjectFull = gProjectPath / gProjectName

  gProjectMainIdx = addFileExt(gProjectFull, NimExt).fileInfoIdx

proc mainCommand* =
  # In "nimrod serve" scenario, each command must reset the registered passes
  clearPasses()
  gLastCmdTime = epochTime()
  appendStr(searchPaths, options.libpath)
  if gProjectFull.len != 0:
    # current path is always looked first for modules
    prependStr(searchPaths, gProjectPath)
  setId(100)
  passes.gIncludeFile = includeModule
  passes.gImportModule = importModule
  case command.normalize
  of "c", "cc", "compile", "compiletoc":
    # compile means compileToC currently
    gCmd = cmdCompileToC
    wantMainModule()
    commandCompileToC()
  of "cpp", "compiletocpp":
    extccomp.cExt = ".cpp"
    gCmd = cmdCompileToCpp
    if cCompiler == ccGcc: setCC("gcc")
    wantMainModule()
    defineSymbol("cpp")
    commandCompileToC()
  of "objc", "compiletooc":
    extccomp.cExt = ".m"
    gCmd = cmdCompileToOC
    wantMainModule()
    defineSymbol("objc")
    commandCompileToC()
  of "run":
    gCmd = cmdRun
    wantMainModule()
    when hasTinyCBackend:
      extccomp.setCC("tcc")
      commandCompileToC()
    else:
      rawMessage(errInvalidCommandX, command)
  of "js", "compiletojs":
    gCmd = cmdCompileToJS
    wantMainModule()
    commandCompileToJS()
  else:
    rawMessage(errInvalidCommandX, command)

  if (msgs.gErrorCounter == 0 and
      gCmd notin {cmdInterpret, cmdRun, cmdDump} and
      gVerbosity > 0):
    rawMessage(hintSuccessX, [$gLinesCompiled,
               formatFloat(epochTime() - gLastCmdTime, ffDecimal, 3),
               formatSize(getTotalMem())])
