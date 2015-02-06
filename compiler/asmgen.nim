#
#
#           The Nim Compiler
#        (c) Copyright 2015 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
import cgendata, ast, strutils, os, extccomp, options, ropes, strutils, astalgo
import msgs

type
  OpCode = enum
    opcPush, opcMov, opcPop, opcRet, opcAdd, opcSub, opcLeave, opcCmp, opcJe,
    opcJmp, opcJne

  Register = enum
    regRAX, regRDI, regRSI, regRDX, regRCX, regR8, regR9,
    regRBP, regRSP

  ProcSection = enum
    prcHeader, prcBody

  AsmProc = ref object
    stackSlotsCounter: int ## How many stack slots have been used by vars.
    owner: PSym ## The owning nkProcDef
    code: array[ProcSection, string]
    ifStmtNum: int
    elifStmtNum: int

const
  noOperand = {opcRet, opcLeave}
  oneOperand = {opcPush, opcPop, opcJe, opcJmp, opcJne}
  twoOperands = {opcMov, opcAdd, opcSub, opcCmp}

template codeBody(): expr =
  context.code[prcBody]

template codeHeader(): expr =
  context.code[prcHeader]

proc `$`(opc: OpCode): string =
  result = system.`$`(opc)[3 .. -1].toUpper

proc addN(s: var string, y: string) =
  s.add y & "\n"

proc addIndentN(s: var string, y: string) =
  s.addN "\t" & y

proc emit(s: var string, opc: OpCode) =
  assert opc in noOperand
  s.addIndentN($opc)

proc emit(s: var string, opc: OpCode, x: string) =
  assert opc in oneOperand
  s.addIndentN($opc & " " & x)

proc emit(s: var string, opc: OpCode, x, y: string) =
  assert opc in twoOperands
  s.addIndentN($opc & " " & x & ", " & y)

proc `$`(reg: Register): string =
  result = system.`$`(reg)[3 .. -1].toUpper

proc getProcName(context: AsmProc): string =
  context.owner.loc.r.ropeToStr

proc getRegisterParam(pos: int): Register =
  # TODO Windows
  const paramToRegister = [regRDI, regRSI, regRDX, regRCX, regR8, regR9]
  if pos > 5: internalError("TODO: Too many proc params")
  return paramToRegister[pos]

proc getBlockLabel(context: AsmProc, sym: PSym): string =
  context.getProcName() & '.' & sym.name.s & '_' & sym.id

proc toOperand(n: PNode): string =
  case n.kind
  of nkSym:
    case n.sym.kind
    of skParam:
      return $getRegisterParam(n.sym.position)
    of skVar:
      let name = n.sym.name.s & '_' & $n.sym.id
      return "[" & $regRSP & "+" & name & "]"
    else:
      assert false, $n.sym.kind
  of nkIntLit:
    return $n.intVal
  else:
    assert false, $n.kind

proc genAsgn(context: AsmProc, n: PNode, dest: Register)
proc genMagicExpr(context: AsmProc, magic: TMagic, args: seq[PNode],
                  dest: Register) =
  for i in 0 .. <args.len:
    case args[i].kind
    of nkSym, nkIntLit:
      if i == 0:
        codeBody.emit(opcMov, $dest, toOperand(args[i]))
        continue
      case magic
      of mAddI:
        codeBody.emit(opcAdd, $dest, toOperand(args[i]))
      of mSubI:
        codeBody.emit(opcSub, $dest, toOperand(args[i]))
      else:
        assert false, "Unknown magic: " & $magic
    else:
      genAsgn(context, args[i], dest)

proc genMagicCmp(context: AsmProc, magic: TMagic, args: seq[PNode],
                 label: string) =
  case magic
  of mEqI:
    codeBody.emit(opcCmp, toOperand(args[0]), toOperand(args[1]))
    codeBody.emit(opcJne, label)
  else:
    assert false, "Unknown magic: " & $magic

proc genAsgn(context: AsmProc, n: PNode, dest: Register) =
  case n.kind
  of nkCallKinds:
    assert n.sons[0].kind == nkSym
    if n.sons[0].sym.magic != mNone:
      genMagicExpr(context, n.sons[0].sym.magic, n.sons[1 .. -1], dest)
    else:
      assert false
  of nkSym, nkIntLit:
    codeBody.emit(opcMov, $dest, toOperand(n))
  else:
    assert false, $n.kind

proc genIfCond(context: AsmProc, n: PNode, label: string) =
  case n.kind
  of nkCallKinds:
    assert n.sons[0].kind == nkSym
    assert n.sons[0].sym.magic != mNone
    context.genMagicCmp(n.sons[0].sym.magic, n.sons[1 .. -1], label)
  else:
    assert false, $n.kind

proc genVars(context: AsmProc, n: PNode) =
  assert n.kind == nkIdentDefs
  var i = 0
  while i < n.sons.len:
    assert n.sons[i].kind == nkSym
    debug n.sons[i].sym
    let name = n.sons[i].sym.name.s & '_' & $n.sons[i].sym.id
    let offset = context.stackSlotsCounter * 8
    codeBody.addIndentN(name & " equ " & $offset)
    codeBody.emit(opcMov, "QWORD " & toOperand(n.sons[i]), toOperand(n.sons[i+2]))
    context.stackSlotsCounter.inc
    i.inc 3

proc genProcBody(context: AsmProc, n: PNode)
proc genIfStmt(context: AsmProc, n: PNode) =
  context.elifStmtNum = 0
  let endIfLabel = ".endIf" & $context.ifStmtNum
  for i in 0 .. <n.sons.len:
    case n.sons[i].kind
    of nkElifBranch:
      let nextBranchLabel =
          ".nextBranch" & $context.ifStmtNum & $context.elifStmtNum
      genIfCond(context, n.sons[i][0], context.getProcName() & nextBranchLabel)
      genProcBody(context, n.sons[i][1])
      codeBody.emit(opcJmp, context.getProcName() & endIfLabel)
      codeBody.addN(nextBranchLabel & ":")
      context.elifStmtNum.inc()
    of nkElse:
      genProcBody(context, n.sons[i][0])
    else:
      internalError("Unexpected node kind in if stmt: " & $n.sons[i].kind)
  codeBody.addN(endIfLabel & ":")
  
  context.ifStmtNum.inc

proc genProcBody(context: AsmProc, n: PNode) =
  ## Generates asm code for the body of a nkProcDef
  case n.kind
  of nkStmtList:
    for i in 0 .. <n.sons.len:
      genProcBody(context, n.sons[i])
  of nkAsgn:
    assert n.sons[0].kind == nkSym
    
    case n.sons[0].sym.kind
    of skResult:
      # We map this to RAX.
      genAsgn(context, n.sons[1], regRAX)
    else:
      assert false
  of nkVarSection:
    genVars(context, n.sons[0])
  of nkIfStmt:
    genIfStmt(context, n)
  of nkBlockStmt:
    assert n.sons[0].kind == nkSym
    codeBody.addN(getBlockLabel(context, n.sons[0].sym) & ':')
    genProcBody(context, n.sons[1])
  of nkEmpty: discard
  else:
    assert false, $n.kind

proc newAsmProc(prc: PSym): AsmProc =
  new result
  result.stackSlotsCounter = 0
  result.owner = prc
  for i in low(result.code)..high(result.code):
    result.code[i] = ""

proc genProc*(m: BModule, prc: PSym) =
  var context = newAsmProc(prc)
  assert prc.ast.kind == nkProcDef
  let nameStr = getProcName(context)
  context.code[prcHeader].addN nameStr & ":"
  
  # Add code for initialising the stack frame properly.
  # TODO: Only do this for debug mode.
  context.code[prcHeader].emit(opcPush, "rbp")
  context.code[prcHeader].emit(opcMov, "rbp", "rsp")
  
  genProcBody(context, prc.ast[6])
  
  # Reserve stack space for local variables
  var reserveSize = context.stackSlotsCounter*8
  if reserveSize != 0:
    if reserveSize mod 16 != 0: reserveSize.inc 8
    context.code[prcHeader].emit(opcSub, $regRSP, $reserveSize)
  
  context.code[prcBody].emit(opcLeave)
  context.code[prcBody].emit(opcRet)
  m.asmSections[afsProcs].addN context.code[prcHeader]
  m.asmSections[afsProcs].addN context.code[prcBody]
  m.asmSections[afsGlobals].addIndentN "global " & nameStr

proc getAsmFilename(m: BModule): string =
  result = changeFileExt(completeCFilePath(m.cfilename.withPackageName), "asm")
  var (head, tail) = splitPath(result)
  result = head / "asm_" & tail

proc writeModule*(m: BModule) =
  ## Writes the specified module's assembly code to a file.
  let filename = getAsmFilename(m)
  echo(filename)
  var contents = ""
  contents.addIndentN("section .text")
  contents.addN(
    m.asmSections[afsGlobals] &
    m.asmSections[afsProcs])
  writeFile(filename, contents)

proc compileModule*(m: BModule) =
  let filename = getAsmFilename(m)
  execExternalProgram("yasm -f elf64 -g dwarf2 -o $1 $2 " %
      [filename.changeFileExt("o"), filename])
  addFileToLink(filename.changeFileExt(""))
