#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This include file implements lambda lifting for the transformator.

import
  intsets, strutils, lists, options, ast, astalgo, trees, treetab, msgs, os,
  idents, renderer, types, magicsys, rodread, lowerings, tables

discard """
  The basic approach is that captured vars need to be put on the heap and
  that the calling chain needs to be explicitly modelled. Things to consider:

  proc a =
    var v = 0
    proc b =
      var w = 2

      for x in 0..3:
        proc c = capture v, w, x
        c()
    b()

    for x in 0..4:
      proc d = capture x
      d()

  Needs to be translated into:

  proc a =
    var cl: *
    new cl
    cl.v = 0

    proc b(cl) =
      var bcl: *
      new bcl
      bcl.w = 2
      bcl.up = cl

      for x in 0..3:
        var bcl2: *
        new bcl2
        bcl2.up = bcl
        bcl2.up2 = cl
        bcl2.x = x

        proc c(cl) = capture cl.up2.v, cl.up.w, cl.x
        c(bcl2)

      c(bcl)

    b(cl)

    for x in 0..4:
      var acl2: *
      new acl2
      acl2.x = x
      proc d(cl) = capture cl.x
      d(acl2)

  Closures as interfaces:

  proc outer: T =
    var captureMe: TObject # value type required for efficiency
    proc getter(): int = result = captureMe.x
    proc setter(x: int) = captureMe.x = x

    result = (getter, setter)

  Is translated to:

  proc outer: T =
    var cl: *
    new cl

    proc getter(cl): int = result = cl.captureMe.x
    proc setter(cl: *, x: int) = cl.captureMe.x = x

    result = ((cl, getter), (cl, setter))


  For 'byref' capture, the outer proc needs to access the captured var through
  the indirection too. For 'bycopy' capture, the outer proc accesses the var
  not through the indirection.

  Possible optimizations:

  1) If the closure contains a single 'ref' and this
  reference is not re-assigned (check ``sfAddrTaken`` flag) make this the
  closure. This is an important optimization if closures are used as
  interfaces.
  2) If the closure does not escape, put it onto the stack, not on the heap.
  3) Dataflow analysis would help to eliminate the 'up' indirections.
  4) If the captured var is not actually used in the outer proc (common?),
  put it into an inner proc.

"""

# Important things to keep in mind:
# * Don't base the analysis on nkProcDef et al. This doesn't work for
#   instantiated (formerly generic) procs. The analysis has to look at nkSym.
#   This also means we need to prevent the same proc is processed multiple
#   times via the 'processed' set.
# * Keep in mind that the owner of some temporaries used to be unreliable.
# * For closure iterators we merge the "real" potential closure with the
#   local storage requirements for efficiency. This means closure iterators
#   have slightly different semantics from ordinary closures.

# ---------------- essential helpers -------------------------------------

const
  upName* = ":up" # field name for the 'up' reference
  paramName* = ":envP"
  envName* = ":env"

proc newCall(a: PSym, b: PNode): PNode =
  result = newNodeI(nkCall, a.info)
  result.add newSymNode(a)
  result.add b

proc createStateType(iter: PSym): PType =
  var n = newNodeI(nkRange, iter.info)
  addSon(n, newIntNode(nkIntLit, -1))
  addSon(n, newIntNode(nkIntLit, 0))
  result = newType(tyRange, iter)
  result.n = n
  var intType = nilOrSysInt()
  if intType.isNil: intType = newType(tyInt, iter)
  rawAddSon(result, intType)

proc createStateField(iter: PSym): PSym =
  result = newSym(skField, getIdent(":state"), iter, iter.info)
  result.typ = createStateType(iter)

proc createEnvObj(owner: PSym; info: TLineInfo): PType =
  # YYY meh, just add the state field for every closure for now, it's too
  # hard to figure out if it comes from a closure iterator:
  result = createObj(owner, info)
  rawAddField(result, createStateField(owner))

proc getIterResult(iter: PSym): PSym =
  if resultPos < iter.ast.len:
    result = iter.ast.sons[resultPos].sym
  else:
    # XXX a bit hacky:
    result = newSym(skResult, getIdent":result", iter, iter.info)
    result.typ = iter.typ.sons[0]
    incl(result.flags, sfUsed)
    iter.ast.add newSymNode(result)

proc addHiddenParam(routine: PSym, param: PSym) =
  assert param.kind == skParam
  var params = routine.ast.sons[paramsPos]
  # -1 is correct here as param.position is 0 based but we have at position 0
  # some nkEffect node:
  param.position = routine.typ.n.len-1
  addSon(params, newSymNode(param))
  #incl(routine.typ.flags, tfCapturesEnv)
  assert sfFromGeneric in param.flags
  #echo "produced environment: ", param.id, " for ", routine.id

proc getHiddenParam(routine: PSym): PSym =
  let params = routine.ast.sons[paramsPos]
  let hidden = lastSon(params)
  if hidden.kind == nkSym and hidden.sym.kind == skParam and hidden.sym.name.s == paramName:
    result = hidden.sym
    assert sfFromGeneric in result.flags
  else:
    # writeStackTrace()
    localError(routine.info, "internal error: could not find env param for " & routine.name.s)
    result = routine

proc getEnvParam*(routine: PSym): PSym =
  let params = routine.ast.sons[paramsPos]
  let hidden = lastSon(params)
  if hidden.kind == nkSym and hidden.sym.name.s == paramName:
    result = hidden.sym
    assert sfFromGeneric in result.flags

proc interestingVar(s: PSym): bool {.inline.} =
  result = s.kind in {skVar, skLet, skTemp, skForVar, skParam, skResult} and
    sfGlobal notin s.flags

proc illegalCapture(s: PSym): bool {.inline.} =
  result = skipTypes(s.typ, abstractInst).kind in
                   {tyVar, tyOpenArray, tyVarargs} or
      s.kind == skResult

proc isInnerProc(s: PSym): bool =
  if s.kind in {skProc, skMethod, skConverter, skIterator} and s.magic == mNone:
    result = s.skipGenericOwner.kind in routineKinds

proc newAsgnStmt(le, ri: PNode, info: TLineInfo): PNode =
  # Bugfix: unfortunately we cannot use 'nkFastAsgn' here as that would
  # mean to be able to capture string literals which have no GC header.
  # However this can only happen if the capture happens through a parameter,
  # which is however the only case when we generate an assignment in the first
  # place.
  result = newNodeI(nkAsgn, info, 2)
  result.sons[0] = le
  result.sons[1] = ri

proc makeClosure*(prc: PSym; env: PNode; info: TLineInfo): PNode =
  result = newNodeIT(nkClosure, info, prc.typ)
  result.add(newSymNode(prc))
  if env == nil:
    result.add(newNodeIT(nkNilLit, info, getSysType(tyNil)))
  else:
    if env.skipConv.kind == nkClosure:
      localError(info, "internal error: taking closure of closure")
    result.add(env)

proc interestingIterVar(s: PSym): bool {.inline.} =
  # XXX optimization: Only lift the variable if it lives across
  # yield/return boundaries! This can potentially speed up
  # closure iterators quite a bit.
  result = s.kind in {skVar, skLet, skTemp, skForVar} and sfGlobal notin s.flags

template isIterator*(owner: PSym): bool =
  owner.kind == skIterator and owner.typ.callConv == ccClosure

proc liftingHarmful(owner: PSym): bool {.inline.} =
  ## lambda lifting can be harmful for JS-like code generators.
  let isCompileTime = sfCompileTime in owner.flags or owner.kind == skMacro
  result = gCmd in {cmdCompileToPHP, cmdCompileToJS} and not isCompileTime

proc liftIterSym*(n: PNode; owner: PSym): PNode =
  # transforms  (iter)  to  (let env = newClosure[iter](); (iter, env))
  if liftingHarmful(owner): return n
  let iter = n.sym
  assert iter.isIterator

  result = newNodeIT(nkStmtListExpr, n.info, n.typ)

  let hp = getHiddenParam(iter)
  var env: PNode
  if owner.isIterator:
    let it = getHiddenParam(owner)
    addUniqueField(it.typ.sons[0], hp)
    env = indirectAccess(newSymNode(it), hp, hp.info)
  else:
    let e = newSym(skLet, iter.name, owner, n.info)
    e.typ = hp.typ
    e.flags = hp.flags
    env = newSymNode(e)
    var v = newNodeI(nkVarSection, n.info)
    addVar(v, env)
    result.add(v)
  # add 'new' statement:
  result.add newCall(getSysSym"internalNew", env)
  result.add makeClosure(iter, env, n.info)

proc freshVarForClosureIter*(s, owner: PSym): PNode =
  let envParam = getHiddenParam(owner)
  let obj = envParam.typ.lastSon
  addField(obj, s)

  var access = newSymNode(envParam)
  assert obj.kind == tyObject
  let field = getFieldFromObj(obj, s)
  if field != nil:
    result = rawIndirectAccess(access, field, s.info)
  else:
    localError(s.info, "internal error: cannot generate fresh variable")
    result = access

# ------------------ new stuff -------------------------------------------

proc markAsClosure(owner: PSym; n: PNode) =
  let s = n.sym
  if illegalCapture(s) or owner.typ.callConv notin {ccClosure, ccDefault}:
    localError(n.info, errIllegalCaptureX, s.name.s)
  incl(owner.typ.flags, tfCapturesEnv)
  owner.typ.callConv = ccClosure

type
  DetectionPass = object
    processed, capturedVars: IntSet
    ownerToType: Table[int, PType]
    somethingToDo: bool

proc initDetectionPass(fn: PSym): DetectionPass =
  result.processed = initIntSet()
  result.capturedVars = initIntSet()
  result.ownerToType = initTable[int, PType]()
  result.processed.incl(fn.id)

discard """
proc outer =
  var a, b: int
  proc innerA = use(a)
  proc innerB = use(b); innerA()
# --> innerA and innerB need to *share* the closure type!
This is why need to store the 'ownerToType' table and use it
during .closure'fication.
"""

proc getEnvTypeForOwner(c: var DetectionPass; owner: PSym;
                        info: TLineInfo): PType =
  result = c.ownerToType.getOrDefault(owner.id)
  if result.isNil:
    result = newType(tyRef, owner)
    let obj = createEnvObj(owner, info)
    rawAddSon(result, obj)
    c.ownerToType[owner.id] = result

proc createUpField(c: var DetectionPass; dest, dep: PSym; info: TLineInfo) =
  let refObj = c.getEnvTypeForOwner(dest, info) # getHiddenParam(dest).typ
  let obj = refObj.lastSon
  let fieldType = c.getEnvTypeForOwner(dep, info) #getHiddenParam(dep).typ
  if refObj == fieldType:
    localError(dep.info, "internal error: invalid up reference computed")

  let upIdent = getIdent(upName)
  let upField = lookupInRecord(obj.n, upIdent)
  if upField != nil:
    if upField.typ != fieldType:
      localError(dep.info, "internal error: up references do not agree")
  else:
    let result = newSym(skField, upIdent, obj.owner, obj.owner.info)
    result.typ = fieldType
    rawAddField(obj, result)

discard """
There are a couple of possibilities of how to implement closure
iterators that capture outer variables in a traditional sense
(aka closure closure iterators).

1. Transform iter() to  iter(state, capturedEnv). So use 2 hidden
   parameters.
2. Add the captured vars directly to 'state'.
3. Make capturedEnv an up-reference of 'state'.

We do (3) here because (2) is obviously wrong and (1) is wrong too.
Consider:

  proc outer =
    var xx = 9

    iterator foo() =
      var someState = 3

      proc bar = echo someState
      proc baz = someState = 0
      baz()
      bar()

"""

proc addClosureParam(c: var DetectionPass; fn: PSym; info: TLineInfo) =
  var cp = getEnvParam(fn)
  let owner = if fn.kind == skIterator: fn else: fn.skipGenericOwner
  let t = c.getEnvTypeForOwner(owner, info)
  if cp == nil:
    cp = newSym(skParam, getIdent(paramName), fn, fn.info)
    incl(cp.flags, sfFromGeneric)
    cp.typ = t
    addHiddenParam(fn, cp)
  elif cp.typ != t and fn.kind != skIterator:
    localError(fn.info, "internal error: inconsistent environment type")
  #echo "adding closure to ", fn.name.s

proc detectCapturedVars(n: PNode; owner: PSym; c: var DetectionPass) =
  case n.kind
  of nkSym:
    let s = n.sym
    if s.kind in {skProc, skMethod, skConverter, skIterator} and s.typ != nil and s.typ.callConv == ccClosure:
      # this handles the case that the inner proc was declared as
      # .closure but does not actually capture anything:
      addClosureParam(c, s, n.info)
      c.somethingToDo = true

    let innerProc = isInnerProc(s)
    if innerProc:
      if s.isIterator: c.somethingToDo = true
      if not c.processed.containsOrIncl(s.id):
        detectCapturedVars(s.getBody, s, c)
    let ow = s.skipGenericOwner
    if ow == owner:
      if owner.isIterator:
        c.somethingToDo = true
        addClosureParam(c, owner, n.info)
        if interestingIterVar(s):
          if not c.capturedVars.containsOrIncl(s.id):
            let obj = getHiddenParam(owner).typ.lastSon
            #let obj = c.getEnvTypeForOwner(s.owner).lastSon
            addField(obj, s)
      # but always return because the rest of the proc is only relevant when
      # ow != owner:
      return
    # direct or indirect dependency:
    if (innerProc and s.typ.callConv == ccClosure) or interestingVar(s):
      discard """
        proc outer() =
          var x: int
          proc inner() =
            proc innerInner() =
              echo x
            innerInner()
          inner()
        # inner() takes a closure too!
      """
      # mark 'owner' as taking a closure:
      c.somethingToDo = true
      markAsClosure(owner, n)
      addClosureParam(c, owner, n.info)
      #echo "capturing ", n.info
      # variable 's' is actually captured:
      if interestingVar(s) and not c.capturedVars.containsOrIncl(s.id):
        let obj = c.getEnvTypeForOwner(ow, n.info).lastSon
        #getHiddenParam(owner).typ.lastSon
        addField(obj, s)
      # create required upFields:
      var w = owner.skipGenericOwner
      if isInnerProc(w) or owner.isIterator:
        if owner.isIterator: w = owner
        let last = if ow.isIterator: ow.skipGenericOwner else: ow
        while w != nil and w.kind != skModule and last != w:
          discard """
          proc outer =
            var a, b: int
            proc outerB =
              proc innerA = use(a)
              proc innerB = use(b); innerA()
          # --> make outerB of calling convention .closure and
          # give it the same env type that outer's env var gets:
          """
          let up = w.skipGenericOwner
          #echo "up for ", w.name.s, " up ", up.name.s
          markAsClosure(w, n)
          addClosureParam(c, w, n.info) # , ow
          createUpField(c, w, up, n.info)
          w = up
  of nkEmpty..pred(nkSym), succ(nkSym)..nkNilLit,
     nkTemplateDef, nkTypeSection:
    discard
  of nkProcDef, nkMethodDef, nkConverterDef, nkMacroDef:
    discard
  of nkLambdaKinds, nkIteratorDef:
    if n.typ != nil:
      detectCapturedVars(n[namePos], owner, c)
  else:
    for i in 0..<n.len:
      detectCapturedVars(n[i], owner, c)

type
  LiftingPass = object
    processed: IntSet
    envVars: Table[int, PNode]

proc initLiftingPass(fn: PSym): LiftingPass =
  result.processed = initIntSet()
  result.processed.incl(fn.id)
  result.envVars = initTable[int, PNode]()

proc accessViaEnvParam(n: PNode; owner: PSym): PNode =
  let s = n.sym
  # Type based expression construction for simplicity:
  let envParam = getHiddenParam(owner)
  if not envParam.isNil:
    var access = newSymNode(envParam)
    while true:
      let obj = access.typ.sons[0]
      assert obj.kind == tyObject
      let field = getFieldFromObj(obj, s)
      if field != nil:
        return rawIndirectAccess(access, field, n.info)
      let upField = lookupInRecord(obj.n, getIdent(upName))
      if upField == nil: break
      access = rawIndirectAccess(access, upField, n.info)
  localError(n.info, "internal error: environment misses: " & s.name.s)
  result = n

proc newEnvVar(owner: PSym; typ: PType): PNode =
  var v = newSym(skVar, getIdent(envName), owner, owner.info)
  incl(v.flags, sfShadowed)
  v.typ = typ
  result = newSymNode(v)
  when false:
    if owner.kind == skIterator and owner.typ.callConv == ccClosure:
      let it = getHiddenParam(owner)
      addUniqueField(it.typ.sons[0], v)
      result = indirectAccess(newSymNode(it), v, v.info)
    else:
      result = newSymNode(v)

proc setupEnvVar(owner: PSym; d: DetectionPass;
                 c: var LiftingPass): PNode =
  if owner.isIterator:
    return getHiddenParam(owner).newSymNode
  result = c.envvars.getOrDefault(owner.id)
  if result.isNil:
    let envVarType = d.ownerToType.getOrDefault(owner.id)
    if envVarType.isNil:
      localError owner.info, "internal error: could not determine closure type"
    result = newEnvVar(owner, envVarType)
    c.envVars[owner.id] = result

proc getUpViaParam(owner: PSym): PNode =
  let p = getHiddenParam(owner)
  result = p.newSymNode
  if owner.isIterator:
    let upField = lookupInRecord(p.typ.lastSon.n, getIdent(upName))
    if upField == nil:
      localError(owner.info, "could not find up reference for closure iter")
    else:
      result = rawIndirectAccess(result, upField, p.info)

proc rawClosureCreation(owner: PSym;
                        d: DetectionPass; c: var LiftingPass): PNode =
  result = newNodeI(nkStmtList, owner.info)

  var env: PNode
  if owner.isIterator:
    env = getHiddenParam(owner).newSymNode
  else:
    env = setupEnvVar(owner, d, c)
    if env.kind == nkSym:
      var v = newNodeI(nkVarSection, env.info)
      addVar(v, env)
      result.add(v)
    # add 'new' statement:
    result.add(newCall(getSysSym"internalNew", env))
    # add assignment statements for captured parameters:
    for i in 1..<owner.typ.n.len:
      let local = owner.typ.n[i].sym
      if local.id in d.capturedVars:
        let fieldAccess = indirectAccess(env, local, env.info)
        # add ``env.param = param``
        result.add(newAsgnStmt(fieldAccess, newSymNode(local), env.info))

  let upField = lookupInRecord(env.typ.lastSon.n, getIdent(upName))
  if upField != nil:
    let up = getUpViaParam(owner)
    if up != nil and upField.typ == up.typ:
      result.add(newAsgnStmt(rawIndirectAccess(env, upField, env.info),
                 up, env.info))
    #elif oldenv != nil and oldenv.typ == upField.typ:
    #  result.add(newAsgnStmt(rawIndirectAccess(env, upField, env.info),
    #             oldenv, env.info))
    else:
      localError(env.info, "internal error: cannot create up reference")

proc closureCreationForIter(iter: PNode;
                            d: DetectionPass; c: var LiftingPass): PNode =
  result = newNodeIT(nkStmtListExpr, iter.info, iter.sym.typ)
  let owner = iter.sym.skipGenericOwner
  var v = newSym(skVar, getIdent(envName), owner, iter.info)
  incl(v.flags, sfShadowed)
  v.typ = getHiddenParam(iter.sym).typ
  var vnode: PNode
  if owner.isIterator:
    let it = getHiddenParam(owner)
    addUniqueField(it.typ.sons[0], v)
    vnode = indirectAccess(newSymNode(it), v, v.info)
  else:
    vnode = v.newSymNode
    var vs = newNodeI(nkVarSection, iter.info)
    addVar(vs, vnode)
    result.add(vs)
  result.add(newCall(getSysSym"internalNew", vnode))

  let upField = lookupInRecord(v.typ.lastSon.n, getIdent(upName))
  if upField != nil:
    let u = setupEnvVar(owner, d, c)
    if u.typ == upField.typ:
      result.add(newAsgnStmt(rawIndirectAccess(vnode, upField, iter.info),
                 u, iter.info))
    else:
      localError(iter.info, "internal error: cannot create up reference for iter")
  result.add makeClosure(iter.sym, vnode, iter.info)

proc accessViaEnvVar(n: PNode; owner: PSym; d: DetectionPass;
                     c: var LiftingPass): PNode =
  let access = setupEnvVar(owner, d, c)
  let obj = access.typ.sons[0]
  let field = getFieldFromObj(obj, n.sym)
  if field != nil:
    result = rawIndirectAccess(access, field, n.info)
  else:
    localError(n.info, "internal error: not part of closure object type")
    result = n

proc getStateField(owner: PSym): PSym =
  getHiddenParam(owner).typ.sons[0].n.sons[0].sym

proc liftCapturedVars(n: PNode; owner: PSym; d: DetectionPass;
                      c: var LiftingPass): PNode

proc transformYield(n: PNode; owner: PSym; d: DetectionPass;
                    c: var LiftingPass): PNode =
  let state = getStateField(owner)
  assert state != nil
  assert state.typ != nil
  assert state.typ.n != nil
  inc state.typ.n.sons[1].intVal
  let stateNo = state.typ.n.sons[1].intVal

  var stateAsgnStmt = newNodeI(nkAsgn, n.info)
  stateAsgnStmt.add(rawIndirectAccess(newSymNode(getEnvParam(owner)),
                    state, n.info))
  stateAsgnStmt.add(newIntTypeNode(nkIntLit, stateNo, getSysType(tyInt)))

  var retStmt = newNodeI(nkReturnStmt, n.info)
  if n.sons[0].kind != nkEmpty:
    var a = newNodeI(nkAsgn, n.sons[0].info)
    var retVal = liftCapturedVars(n.sons[0], owner, d, c)
    addSon(a, newSymNode(getIterResult(owner)))
    addSon(a, retVal)
    retStmt.add(a)
  else:
    retStmt.add(emptyNode)

  var stateLabelStmt = newNodeI(nkState, n.info)
  stateLabelStmt.add(newIntTypeNode(nkIntLit, stateNo, getSysType(tyInt)))

  result = newNodeI(nkStmtList, n.info)
  result.add(stateAsgnStmt)
  result.add(retStmt)
  result.add(stateLabelStmt)

proc transformReturn(n: PNode; owner: PSym; d: DetectionPass;
                     c: var LiftingPass): PNode =
  let state = getStateField(owner)
  result = newNodeI(nkStmtList, n.info)
  var stateAsgnStmt = newNodeI(nkAsgn, n.info)
  stateAsgnStmt.add(rawIndirectAccess(newSymNode(getEnvParam(owner)),
                    state, n.info))
  stateAsgnStmt.add(newIntTypeNode(nkIntLit, -1, getSysType(tyInt)))
  result.add(stateAsgnStmt)
  result.add(n)

proc wrapIterBody(n: PNode; owner: PSym): PNode =
  if not owner.isIterator: return n
  when false:
    # unfortunately control flow is still convoluted and we can end up
    # multiple times here for the very same iterator. We shield against this
    # with some rather primitive check for now:
    if n.kind == nkStmtList and n.len > 0:
      if n.sons[0].kind == nkGotoState: return n
      if n.len > 1 and n[1].kind == nkStmtList and n[1].len > 0 and
          n[1][0].kind == nkGotoState:
        return n
  let info = n.info
  result = newNodeI(nkStmtList, info)
  var gs = newNodeI(nkGotoState, info)
  gs.add(rawIndirectAccess(newSymNode(owner.getHiddenParam), getStateField(owner), info))
  result.add(gs)
  var state0 = newNodeI(nkState, info)
  state0.add(newIntNode(nkIntLit, 0))
  result.add(state0)

  result.add(n)

  var stateAsgnStmt = newNodeI(nkAsgn, info)
  stateAsgnStmt.add(rawIndirectAccess(newSymNode(owner.getHiddenParam),
                    getStateField(owner), info))
  stateAsgnStmt.add(newIntTypeNode(nkIntLit, -1, getSysType(tyInt)))
  result.add(stateAsgnStmt)

proc symToClosure(n: PNode; owner: PSym; d: DetectionPass;
                  c: var LiftingPass): PNode =
  let s = n.sym
  if s == owner:
    # recursive calls go through (lambda, hiddenParam):
    let available = getHiddenParam(owner)
    result = makeClosure(s, available.newSymNode, n.info)
  elif s.isIterator:
    result = closureCreationForIter(n, d, c)
  elif s.skipGenericOwner == owner:
    # direct dependency, so use the outer's env variable:
    result = makeClosure(s, setupEnvVar(owner, d, c), n.info)
  else:
    let available = getHiddenParam(owner)
    let wanted = getHiddenParam(s).typ
    # ugh: call through some other inner proc;
    var access = newSymNode(available)
    while true:
      if access.typ == wanted:
        return makeClosure(s, access, n.info)
      let obj = access.typ.sons[0]
      let upField = lookupInRecord(obj.n, getIdent(upName))
      if upField == nil:
        localError(n.info, "internal error: no environment found")
        return n
      access = rawIndirectAccess(access, upField, n.info)

proc liftCapturedVars(n: PNode; owner: PSym; d: DetectionPass;
                      c: var LiftingPass): PNode =
  result = n
  case n.kind
  of nkSym:
    let s = n.sym
    if isInnerProc(s):
      if not c.processed.containsOrIncl(s.id):
        #if s.name.s == "temp":
        #  echo renderTree(s.getBody, {renderIds})
        let body = wrapIterBody(liftCapturedVars(s.getBody, s, d, c), s)
        if c.envvars.getOrDefault(s.id).isNil:
          s.ast.sons[bodyPos] = body
        else:
          s.ast.sons[bodyPos] = newTree(nkStmtList, rawClosureCreation(s, d, c), body)
      if s.typ.callConv == ccClosure:
        result = symToClosure(n, owner, d, c)
    elif s.id in d.capturedVars:
      if s.owner != owner:
        result = accessViaEnvParam(n, owner)
      elif owner.isIterator and interestingIterVar(s):
        result = accessViaEnvParam(n, owner)
      else:
        result = accessViaEnvVar(n, owner, d, c)
  of nkEmpty..pred(nkSym), succ(nkSym)..nkNilLit,
     nkTemplateDef, nkTypeSection:
    discard
  of nkProcDef, nkMethodDef, nkConverterDef, nkMacroDef:
    discard
  of nkClosure:
    if n[1].kind == nkNilLit:
      n.sons[0] = liftCapturedVars(n[0], owner, d, c)
      let x = n.sons[0].skipConv
      if x.kind == nkClosure:
        #localError(n.info, "internal error: closure to closure created")
        # now we know better, so patch it:
        n.sons[0] = x.sons[0]
        n.sons[1] = x.sons[1]
  of nkLambdaKinds, nkIteratorDef:
    if n.typ != nil and n[namePos].kind == nkSym:
      let m = newSymNode(n[namePos].sym)
      m.typ = n.typ
      result = liftCapturedVars(m, owner, d, c)
  of nkHiddenStdConv:
    if n.len == 2:
      n.sons[1] = liftCapturedVars(n[1], owner, d, c)
      if n[1].kind == nkClosure: result = n[1]
  else:
    if owner.isIterator:
      if n.kind == nkYieldStmt:
        return transformYield(n, owner, d, c)
      elif n.kind == nkReturnStmt:
        return transformReturn(n, owner, d, c)
      elif nfLL in n.flags:
        # special case 'when nimVm' due to bug #3636:
        n.sons[1] = liftCapturedVars(n[1], owner, d, c)
        return
    for i in 0..<n.len:
      n.sons[i] = liftCapturedVars(n[i], owner, d, c)

# ------------------ old stuff -------------------------------------------

proc semCaptureSym*(s, owner: PSym) =
  if interestingVar(s) and s.kind != skResult:
    if owner.typ != nil and not isGenericRoutine(owner):
      # XXX: is this really safe?
      # if we capture a var from another generic routine,
      # it won't be consider captured.
      var o = owner.skipGenericOwner
      while o.kind != skModule and o != nil:
        if s.owner == o:
          owner.typ.callConv = ccClosure
          #echo "computing .closure for ", owner.name.s, " ", owner.info, " because of ", s.name.s
        o = o.skipGenericOwner
    # since the analysis is not entirely correct, we don't set 'tfCapturesEnv'
    # here

proc liftIterToProc*(fn: PSym; body: PNode; ptrType: PType): PNode =
  var d = initDetectionPass(fn)
  var c = initLiftingPass(fn)
  # pretend 'fn' is a closure iterator for the analysis:
  let oldKind = fn.kind
  let oldCC = fn.typ.callConv
  fn.kind = skIterator
  fn.typ.callConv = ccClosure
  d.ownerToType[fn.id] = ptrType
  detectCapturedVars(body, fn, d)
  result = wrapIterBody(liftCapturedVars(body, fn, d, c), fn)
  fn.kind = oldKind
  fn.typ.callConv = oldCC

proc liftLambdas*(fn: PSym, body: PNode; tooEarly: var bool): PNode =
  # XXX gCmd == cmdCompileToJS does not suffice! The compiletime stuff needs
  # the transformation even when compiling to JS ...

  # However we can do lifting for the stuff which is *only* compiletime.
  let isCompileTime = sfCompileTime in fn.flags or fn.kind == skMacro

  if body.kind == nkEmpty or (
      gCmd in {cmdCompileToPHP, cmdCompileToJS} and not isCompileTime) or
      fn.skipGenericOwner.kind != skModule:
    # ignore forward declaration:
    result = body
    tooEarly = true
  else:
    var d = initDetectionPass(fn)
    detectCapturedVars(body, fn, d)
    if not d.somethingToDo and fn.isIterator:
      addClosureParam(d, fn, body.info)
      d.somethingToDo = true
    if d.somethingToDo:
      var c = initLiftingPass(fn)
      var newBody = liftCapturedVars(body, fn, d, c)
      if c.envvars.getOrDefault(fn.id) != nil:
        newBody = newTree(nkStmtList, rawClosureCreation(fn, d, c), newBody)
      result = wrapIterBody(newBody, fn)
    else:
      result = body
    #if fn.name.s == "get2":
    #  echo "had something to do ", d.somethingToDo
    #  echo renderTree(result, {renderIds})

proc liftLambdasForTopLevel*(module: PSym, body: PNode): PNode =
  if body.kind == nkEmpty or gCmd == cmdCompileToJS:
    result = body
  else:
    # XXX implement it properly
    result = body

# ------------------- iterator transformation --------------------------------

proc liftForLoop*(body: PNode; owner: PSym): PNode =
  # problem ahead: the iterator could be invoked indirectly, but then
  # we don't know what environment to create here:
  #
  # iterator count(): int =
  #   yield 0
  #
  # iterator count2(): int =
  #   var x = 3
  #   yield x
  #   inc x
  #   yield x
  #
  # proc invoke(iter: iterator(): int) =
  #   for x in iter(): echo x
  #
  # --> When to create the closure? --> for the (count) occurrence!
  discard """
      for i in foo(): ...

    Is transformed to:

      cl = createClosure()
      while true:
        let i = foo(cl)
        nkBreakState(cl.state)
        ...
    """
  if liftingHarmful(owner): return body
  var L = body.len
  if not (body.kind == nkForStmt and body[L-2].kind in nkCallKinds):
    localError(body.info, "ignored invalid for loop")
    return body
  var call = body[L-2]

  result = newNodeI(nkStmtList, body.info)

  # static binding?
  var env: PSym
  let op = call[0]
  if op.kind == nkSym and op.sym.isIterator:
    # createClosure()
    let iter = op.sym

    let hp = getHiddenParam(iter)
    env = newSym(skLet, iter.name, owner, body.info)
    env.typ = hp.typ
    env.flags = hp.flags

    var v = newNodeI(nkVarSection, body.info)
    addVar(v, newSymNode(env))
    result.add(v)
    # add 'new' statement:
    result.add(newCall(getSysSym"internalNew", env.newSymNode))
  elif op.kind == nkStmtListExpr:
    let closure = op.lastSon
    if closure.kind == nkClosure:
      call.sons[0] = closure
      for i in 0 .. op.len-2:
        result.add op[i]

  var loopBody = newNodeI(nkStmtList, body.info, 3)
  var whileLoop = newNodeI(nkWhileStmt, body.info, 2)
  whileLoop.sons[0] = newIntTypeNode(nkIntLit, 1, getSysType(tyBool))
  whileLoop.sons[1] = loopBody
  result.add whileLoop

  # setup loopBody:
  # gather vars in a tuple:
  var v2 = newNodeI(nkLetSection, body.info)
  var vpart = newNodeI(if L == 3: nkIdentDefs else: nkVarTuple, body.info)
  for i in 0 .. L-3:
    if body[i].kind == nkSym:
      body[i].sym.kind = skLet
    addSon(vpart, body[i])

  addSon(vpart, ast.emptyNode) # no explicit type
  if not env.isNil:
    call.sons[0] = makeClosure(call.sons[0].sym, env.newSymNode, body.info)
  addSon(vpart, call)
  addSon(v2, vpart)

  loopBody.sons[0] = v2
  var bs = newNodeI(nkBreakState, body.info)
  bs.addSon(call.sons[0])
  loopBody.sons[1] = bs
  loopBody.sons[2] = body[L-1]
