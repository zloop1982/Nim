#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains the data structures for the C code generation phase.

import
  ast, astalgo, ropes, passes, options, intsets, lists, platform, sighashes,
  tables

from msgs import TLineInfo

type
  TLabel* = Rope              # for the C generator a label is just a rope
  TCFileSection* = enum       # the sections a generated C file consists of
    cfsMergeInfo,             # section containing merge information
    cfsHeaders,               # section for C include file headers
    cfsForwardTypes,          # section for C forward typedefs
    cfsTypes,                 # section for C typedefs
    cfsSeqTypes,              # section for sequence types only
                              # this is needed for strange type generation
                              # reasons
    cfsFieldInfo,             # section for field information
    cfsTypeInfo,              # section for type information
    cfsProcHeaders,           # section for C procs prototypes
    cfsVars,                  # section for C variable declarations
    cfsData,                  # section for C constant data
    cfsProcs,                 # section for C procs that are not inline
    cfsInitProc,              # section for the C init proc
    cfsTypeInit1,             # section 1 for declarations of type information
    cfsTypeInit2,             # section 2 for init of type information
    cfsTypeInit3,             # section 3 for init of type information
    cfsDebugInit,             # section for init of debug information
    cfsDynLibInit,            # section for init of dynamic library binding
    cfsDynLibDeinit           # section for deinitialization of dynamic
                              # libraries
  TCTypeKind* = enum          # describes the type kind of a C type
    ctVoid, ctChar, ctBool,
    ctInt, ctInt8, ctInt16, ctInt32, ctInt64,
    ctFloat, ctFloat32, ctFloat64, ctFloat128,
    ctUInt, ctUInt8, ctUInt16, ctUInt32, ctUInt64,
    ctArray, ctPtrToArray, ctStruct, ctPtr, ctNimStr, ctNimSeq, ctProc,
    ctCString
  TCFileSections* = array[TCFileSection, Rope] # represents a generated C file
  TCProcSection* = enum       # the sections a generated C proc consists of
    cpsLocals,                # section of local variables for C proc
    cpsInit,                  # section for init of variables for C proc
    cpsStmts                  # section of local statements for C proc
  TCProcSections* = array[TCProcSection, Rope] # represents a generated C proc
  BModule* = ref TCGen
  BProc* = ref TCProc
  TBlock*{.final.} = object
    id*: int                  # the ID of the label; positive means that it
    label*: Rope             # generated text for the label
                              # nil if label is not used
    sections*: TCProcSections # the code beloging
    isLoop*: bool             # whether block is a loop
    nestedTryStmts*: int16    # how many try statements is it nested into
    nestedExceptStmts*: int16 # how many except statements is it nested into
    frameLen*: int16

  TCProc{.final.} = object    # represents C proc that is currently generated
    prc*: PSym                # the Nim proc that this C proc belongs to
    beforeRetNeeded*: bool    # true iff 'BeforeRet' label for proc is needed
    threadVarAccessed*: bool  # true if the proc already accessed some threadvar
    lastLineInfo*: TLineInfo  # to avoid generating excessive 'nimln' statements
    currLineInfo*: TLineInfo  # AST codegen will make this superfluous
    nestedTryStmts*: seq[PNode]   # in how many nested try statements we are
                                  # (the vars must be volatile then)
    inExceptBlock*: int       # are we currently inside an except block?
                              # leaving such scopes by raise or by return must
                              # execute any applicable finally blocks
    finallySafePoints*: seq[Rope]  # For correctly cleaning up exceptions when
                                    # using return in finally statements
    labels*: Natural          # for generating unique labels in the C proc
    blocks*: seq[TBlock]      # nested blocks
    breakIdx*: int            # the block that will be exited
                              # with a regular break
    options*: TOptions        # options that should be used for code
                              # generation; this is the same as prc.options
                              # unless prc == nil
    maxFrameLen*: int         # max length of frame descriptor
    module*: BModule          # used to prevent excessive parameter passing
    withinLoop*: int          # > 0 if we are within a loop
    splitDecls*: int          # > 0 if we are in some context for C++ that
                              # requires 'T x = T()' to become 'T x; x = T()'
                              # (yes, C++ is weird like that)
    gcFrameId*: Natural       # for the GC stack marking
    gcFrameType*: Rope        # the struct {} we put the GC markers into

  TTypeSeq* = seq[PType]
  TypeCache* = Table[SigHash, Rope]

  Codegenflag* = enum
    preventStackTrace,  # true if stack traces need to be prevented
    usesThreadVars,     # true if the module uses a thread var
    frameDeclared,      # hack for ROD support so that we don't declare
                        # a frame var twice in an init proc
    isHeaderFile,       # C source file is the header file
    includesStringh,    # C source file already includes ``<string.h>``
    objHasKidsValid     # whether we can rely on tfObjHasKids


  BModuleList* = ref object of RootObj
    mainModProcs*, mainModInit*, otherModsInit*, mainDatInit*: Rope
    mapping*: Rope             # the generated mapping file (if requested)
    modules*: seq[BModule]     # list of all compiled modules
    forwardedProcsCounter*: int
    generatedHeader*: BModule
    breakPointId*: int
    breakpoints*: Rope # later the breakpoints are inserted into the main proc
    typeInfoMarker*: TypeCache

  TCGen = object of TPassContext # represents a C source file
    s*: TCFileSections        # sections of the C file
    flags*: set[Codegenflag]
    module*: PSym
    filename*: string
    cfilename*: string        # filename of the module (including path,
                              # without extension)
    tmpBase*: Rope            # base for temp identifier generation
    typeCache*: TypeCache     # cache the generated types
    forwTypeCache*: TypeCache # cache for forward declarations of types
    declaredThings*: IntSet   # things we have declared in this .c file
    declaredProtos*: IntSet   # prototypes we have declared in this .c file
    headerFiles*: TLinkedList # needed headers to include
    typeInfoMarker*: TypeCache # needed for generating type information
    initProc*: BProc          # code for init procedure
    postInitProc*: BProc      # code to be executed after the init proc
    preInitProc*: BProc       # code executed before the init proc
    typeStack*: TTypeSeq      # used for type generation
    dataCache*: TNodeTable
    forwardedProcs*: TSymSeq  # keep forwarded procs here
    typeNodes*, nimTypes*: int # used for type info generation
    typeNodesName*, nimTypesName*: Rope # used for type info generation
    labels*: Natural          # for generating unique module-scope names
    extensionLoaders*: array['0'..'9', Rope] # special procs for the
                                              # OpenGL wrapper
    injectStmt*: Rope
    sigConflicts*: CountTable[SigHash]
    g*: BModuleList

proc s*(p: BProc, s: TCProcSection): var Rope {.inline.} =
  # section in the current block
  result = p.blocks[p.blocks.len - 1].sections[s]

proc procSec*(p: BProc, s: TCProcSection): var Rope {.inline.} =
  # top level proc sections
  result = p.blocks[0].sections[s]

proc newProc*(prc: PSym, module: BModule): BProc =
  new(result)
  result.prc = prc
  result.module = module
  if prc != nil: result.options = prc.options
  else: result.options = gOptions
  newSeq(result.blocks, 1)
  result.nestedTryStmts = @[]
  result.finallySafePoints = @[]

proc newModuleList*(): BModuleList =
  BModuleList(modules: @[], typeInfoMarker: initTable[SigHash, Rope]())

iterator cgenModules*(g: BModuleList): BModule =
  for i in 0..high(g.modules):
    # ultimately, we are iterating over the file ids here.
    # some "files" won't have an associated cgen module (like stdin)
    # and we must skip over them.
    if g.modules[i] != nil: yield g.modules[i]
