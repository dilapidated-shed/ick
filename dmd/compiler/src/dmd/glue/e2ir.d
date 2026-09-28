Warning: truncated output (original token count: 64048)
Total output lines: 7678

/**
 * Converts expressions to Intermediate Representation (IR) for the backend.
 *
 * Copyright:   Copyright (C) 1999-2026 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 https://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 https://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/compiler/src/dmd/glue/e2ir.d, _e2ir.d)
 * Documentation: https://dlang.org/phobos/dmd_glue_e2ir.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/compiler/src/dmd/glue/e2ir.d
 */

module dmd.glue.e2ir;

import core.stdc.stdio;
import core.stdc.stddef;
import core.stdc.string;
import core.stdc.time;

import dmd.root.array;
import dmd.root.ctfloat;
import dmd.root.rmem;
import dmd.rootobject;
import dmd.root.stringtable;

import dmd.glue;
import dmd.glue.objc;
import dmd.glue.s2ir;
import dmd.glue.tocsym;
import dmd.glue.toctype;
import dmd.glue.toir;
import dmd.glue.toobj;

import dmd.aggregate;
import dmd.arraytypes;
import dmd.astenums;
import dmd.attrib;
import dmd.canthrow;
import dmd.ctfeexpr;
import dmd.dcast : implicitConvTo;
import dmd.dclass;
import dmd.declaration;
import dmd.denum;
import dmd.dmdparams;
import dmd.dmodule;
import dmd.dscope;
import dmd.dstruct;
import dmd.dsymbol;
import dmd.dsymbolsem : include, _isZeroInit, toAlias, isPOD;
import dmd.dtemplate;
import dmd.expression;
import dmd.expressionsem;
import dmd.funcsem : isVirtual;
import dmd.func;
import dmd.hdrgen;
import dmd.id;
import dmd.init;
import dmd.location;
import dmd.mtype;
import dmd.printast;
import dmd.sideeffect;
import dmd.statement;
import dmd.target;
import dmd.templatesem;
import dmd.tokens;
import dmd.typinf;
import dmd.typesem;
import dmd.visitor;
import dmd.packedmemory;

import dmd.backend.cc;
import dmd.backend.cdef;
import dmd.backend.cgcv;
import dmd.backend.code;
import dmd.backend.cv4;
import dmd.backend.dt;
import dmd.backend.el;
import dmd.backend.global;
import dmd.backend.obj;
import dmd.backend.oper;
import dmd.backend.rtlsym;
import dmd.backend.symtab;
import dmd.backend.ty;
import dmd.backend.type;

import dmd.backend.x86.code_x86;

package(dmd.glue):

alias Elems = Array!(elem *);

import dmd.backend.util2 : mem_malloc2;


private int registerSize() { return _tysize[TYnptr]; }

/*****
 * If variable var is a value that will actually be passed as a reference
 * Params:
 *      var = parameter variable
 * Returns:
 *      true if actually implicitly passed by reference
 */
bool ISX64REF(Declaration var)
{
    if (var.isReference())
    {
        return false; // it's not a value
    }

    if (var.isParameter())
    {
        if (target.os == Target.OS.Windows && target.isX86_64)
        {
            /* Use Microsoft C++ ABI
             * https://docs.microsoft.com/en-us/cpp/build/x64-calling-convention?view=msvc-170#parameter-passing
             * but watch out because the spec doesn't mention copy construction
             */
            return var.type.size(Loc.initial) > registerSize
                || (var.storage_class & STC.lazy_)
                || (var.type.isTypeStruct() && var.type.isTypeStruct().sym.hasCopyConstruction());
        }
        else if (target.os & Target.OS.Windows)
        {
            auto ts = var.type.isTypeStruct();
            return !(var.storage_class & STC.lazy_) && ts && ts.sym.hasMoveCtor && ts.sym.hasCopyCtor;
        }
        else if (target.os & Target.OS.Posix)
        {
            return !(var.storage_class & STC.lazy_) && var.type.isTypeStruct() && !var.type.isTypeStruct().sym.isPOD() ||
                passTypeByRef(target, var.type);
        }
    }

    return false;
}

/* If variable exp of type typ is a reference due to x64 calling conventions
 */
bool ISX64REF(ref IRState irs, Expression exp)
{
    if (irs.target.os == Target.OS.Windows && irs.target.isX86_64)
    {
        return exp.type.size(Loc.initial) > registerSize
               || (exp.type.isTypeStruct() && exp.type.isTypeStruct().sym.hasCopyConstruction());
    }
    else if (irs.target.os & Target.OS.Windows)
    {
        auto ts = exp.type.isTypeStruct();
        return ts && ts.sym.hasMoveCtor && ts.sym.hasCopyCtor;
    }
    else if (irs.target.os & Target.OS.Posix)
    {
        return exp.type.isTypeStruct() && !exp.type.isTypeStruct().sym.isPOD() || passTypeByRef(*irs.target, exp.type);
    }

    return false;
}

/**************************************************
 * Generate a copy from e2 to e1.
 * Params:
 *      e1 = lvalue
 *      e2 = rvalue
 *      t = value type
 *      tx = if !null, then t converted to C type
 * Returns:
 *      generated elem
 */
elem* elAssign(elem* e1, elem* e2, Type t, type* tx)
{
    //printf("e1:\n"); elem_print(e1);
    //printf("e2:\n"); elem_print(e2);
    //if (t) printf("t: %s\n", t.toChars());

    // handle implicit conversion from function pointer to delegate
    if (tybasic(e1.Ety) == TYdelegate &&
        tybasic(e2.Ety) != TYdelegate &&
        typtr(e2.Ety) &&
        tysize(e2.Ety) == tysize(TYnptr))
    {
        e2 = el_pair(TYdelegate, el_long(TYnptr, 0), e2);
    }

    elem* e = el_bin(OPeq, e2.Ety, e1, e2);
    switch (tybasic(e2.Ety))
    {
        case TYarray:
            e.Ejty = e.Ety = TYstruct;
            goto case TYstruct;

        case TYstruct:
            e.Eoper = OPstreq;
            if (!tx)
                tx = Type_toCtype(t);
            //printf("tx:\n"); type_print(tx);
            e.ET = tx;
//            if (type_zeroCopy(tx))
//                e.Eoper = OPcomma;
            break;

        default:
            break;
    }
    return e;
}

/*************************************************
 * Determine if zero bits need to be copied for this backend type
 * Params:
 *      t = backend type
 * Returns:
 *      true if 0 bits
 */
bool type_zeroCopy(type* t)
{
    return type_size(t) == 0 ||
        (tybasic(t.Tty) == TYstruct &&
         (t.Ttag.Stype.Ttag.Sstruct.Sflags & STR0size));
}

/*******************************************************
 * Write read-only string to object file, create a local symbol for it.
 * Makes a copy of str's contents, does not keep a reference to it.
 * Params:
 *      str = string
 *      len = number of code units in string
 *      sz = number of bytes per code unit
 * Returns:
 *      Symbol
 */

Symbol* toStringSymbol(const(char)* str, size_t len, size_t sz)
{
    //printf("toStringSymbol() %s\n", str);
    auto sv = stringTab.update(str, len * sz);
    if (sv.value)
        return sv.value;

    if (target.isAArch64)
    {
        /* Generate string symbol of the form l_str.N
         */
    }

    if (target.os != Target.OS.Windows)
    {
        Symbol* si = out_string_literal(str, cast(uint)len, cast(uint)sz);
        sv.value = si;
        return sv.value;
    }

    /* This should be in the back end, but mangleToBuffer() is
     * in the front end.
     */
    /* The stringTab pools common strings within an object file.
     * Win32 and Win64 use COMDATs to pool common strings across object files.
     */
    /* VC++ uses a name mangling scheme, for example, "hello" is mangled to:
     * ??_C@_05CJBACGMB@hello?$AA@
     *        ^ length
     *         ^^^^^^^^ 8 byte checksum
     * But the checksum algorithm is unknown. Just invent our own.
     */

    import dmd.common.outbuffer : OutBuffer;
    OutBuffer buf;
    buf.writestring("__");

    void printHash()
    {
        // Replace long string with hash of that string
        import dmd.common.blake3;
        //only use the first 16 bytes to match the length of md5
        const hash = blake3((cast(ubyte*)str)[0 .. len * sz]);
        foreach (u; hash[0 .. 16])
        {
            ubyte u1 = u >> 4;
            buf.writeByte(cast(char)((u1 < 10) ? u1 + '0' : u1 + 'A' - 10));
            u1 = u & 0xF;
            buf.writeByte(cast(char)((u1 < 10) ? u1 + '0' : u1 + 'A' - 10));
        }
    }

    const mangleMinLen = 14; // mangling: "__a14_(14*2 chars)" = 6+14*2 = 34

    if (len >= mangleMinLen) // long mangling for sure, use hash
        printHash();
    else
    {
        import dmd.mangle;
        scope StringExp se = new StringExp(Loc.initial, str[0 .. len], len, cast(ubyte)sz, 'c');
        mangleToBuffer(se, buf);   // recycle how strings are mangled for templates

        if (buf.length >= 32 + 2)   // long mangling, replace with hash
        {
            buf.setsize(2);
            printHash();
        }
    }

    Symbol* si;
    si = symbol_calloc(buf[]);
    si.Sclass = SC.comdat;
    si.Stype = type_static_array(cast(uint)(len * sz), tstypes[TYchar]);
    si.Stype.Tcount++;
    type_setmangle(&si.Stype, Mangle.c);
    si.Sflags |= SFLnodebug | SFLartifical;
    si.Sfl = FL.data;
    si.Salignment = cast(ubyte)sz;
    out_readonly_comdat(si, str, cast(uint)(len * sz), cast(uint)sz);

    sv.value = si;
    return sv.value;
}

/*******************************************************
 * Turn StringExp into Symbol.
 */

Symbol* toStringSymbol(StringExp se)
{
    Symbol* si;
    string s;
    const n = cast(int)se.numberOfCodeUnits(0, s);
    if (se.sz == 1)
    {
        const slice = se.peekString();
        si = toStringSymbol(slice.ptr, slice.length, 1);
    }
    else
    {
        auto p = cast(char *)mem.xmalloc(n * se.sz);
        se.writeTo(p, false);
        si = toStringSymbol(p, n, se.sz);
        mem.xfree(p);
    }
    return si;
}

/******************************************************
 * Replace call to GC allocator with call to tracing GC allocator.
 * Params:
 *      irs = to get function from
 *      e = elem to modify in place
 *      loc = to get file/line from
 */

void toTraceGC(ref IRState irs, elem* e, Loc loc)
{
    static immutable RTLSYM[2][5] map =
    [
        [ RTLSYM.CALLFINALIZER, RTLSYM.TRACECALLFINALIZER ],
        [ RTLSYM.CALLINTERFACEFINALIZER, RTLSYM.TRACECALLINTERFACEFINALIZER ],

        [ RTLSYM.ARRAYAPPENDCD, RTLSYM.TRACEARRAYAPPENDCD ],
        [ RTLSYM.ARRAYAPPENDWD, RTLSYM.TRACEARRAYAPPENDWD ],

        [ RTLSYM.ALLOCMEMORY, RTLSYM.TRACEALLOCMEMORY ],
    ];

    if (!irs.params.tracegc || !loc.filename)
        return;

    assert(e.Eoper == OPcall);
    elem* e1 = e.E1;
    assert(e1.Eoper == OPvar);

    auto s = e1.Vsym;
    foreach (ref m; map)
    {
        if (s == getRtlsym(m[0]))
        {
            e1.Vsym = getRtlsym(m[1]);
            e.E2 = el_param(e.E2, filelinefunction(irs, loc));
            return;
        }
    }
    assert(0);
}

/*******************************************
 * Convert Expression to elem, then append destructors for any
 * temporaries created in elem.
 * Params:
 *      e = Expression to convert
 *      irs = context
 *      ehidden = lvalue element to place the value, if any
 * Returns:
 *      generated elem tree
 */

elem* toElemDtor(Expression e, ref IRState irs, elem* ehidden = null)
{
    //printf("Expression.toElemDtor() %s\n", e.toChars());

    /* "may" throw may actually be false if we look at a subset of
     * the function. Here, the subset is `e`. If that subset is nothrow,
     * we can generate much better code for the destructors for that subset,
     * even if the rest of the function throws.
     * If mayThrow is false, it cannot be true for some subset of the function,
     * so no need to check.
     * If calling canThrow() here turns out to be too expensive,
     * it can be enabled only for optimized builds.
     */
    const mayThrowSave = irs.mayThrow;
    if (irs.mayThrow && !canThrow(e, irs.getFunc(), null))
        irs.mayThrow = false;

    const starti = irs.varsInScope.length;
    elem* er;
    if (ehidden)
    {
        // RVO: ensure ehidden is returned.
        // Prevent appendDtors() from copying values.
        er = toElemRVO(e, ehidden, irs);
        elem* eh = el_copytree(ehidden);
        if (tybasic(eh.Ety) == TYnptr)
        {
            eh = el_una(OPind, er.Ety, eh);
            eh.ET = er.ET;
        }
        er = el_combine(er, eh);
    }
    else
        er = toElem(e, irs);
    const endi = irs.varsInScope.length;

    irs.mayThrow = mayThrowSave;

    // Add destructors
    elem* ex = appendDtors(irs, er, starti, endi);
    return ex;
}

/*******************************************
 * Take address of an elem.
 * Accounts for e being an rvalue by assigning the rvalue
 * to a temp.
 * Params:
 *      e = elem to take address of
 *      t = Type of elem
 *      alwaysCopy = when true, always copy e to a tmp
 * Returns:
 *      the equivalent of &e
 */

elem* addressElem(elem* e, Type t, bool alwaysCopy = false)
{
    //printf("addressElem()\n");

    elem **pe  = el_scancommas(&e);

    // For conditional operator, both branches need conversion.
    if ((*pe).Eoper == OPcond)
    {
        elem* ec = (*pe).E2;

        ec.E1 = addressElem(ec.E1, t, alwaysCopy);
        ec.E2 = addressElem(ec.E2, t, alwaysCopy);

        (*pe).Ejty = (*pe).Ety = cast(ubyte)ec.E1.Ety;
        (*pe).ET = ec.E1.ET;

        e.Ety = TYnptr;
        ec.Ety = TYnptr;
        return e;
    }

    static bool hasAddress(elem* e)
    {
        if (e.Eoper == OPeq || e.Eoper == OPstreq)
            e = e.E1;
        return e.Eoper == OPvar || e.Eoper == OPind;
    }

    if (alwaysCopy || !hasAddress(*pe))
    {
        elem* e2 = *pe;
        type* tx;

        // Convert to ((tmp=e2),tmp)
        TY ty;
        if (t && ((ty = t.toBasetype().ty) == Tstruct || ty == Tsarray))
            tx = Type_toCtype(t);
        else if (tybasic(e2.Ety) == TYstruct)
        {
            assert(t);                  // don't know of a case where this can be null
            tx = Type_toCtype(t);
        }
        else
            tx = type_fake(e2.Ety);
        Symbol* stmp = symbol_genauto(tx);

        elem* eeq = elAssign(el_var(stmp), e2, t, tx);
        *pe = el_bin(OPcomma,e2.Ety,eeq,el_var(stmp));
    }

    if ((*pe).Eoper == OPind)
    {
        elem* pea = (*pe).E1;

        if (tybasic(pea.Ety) == TYnptr || tybasic(pea.Ety) == TYimmutPtr)
        {
            *pe = pea;
            for (elem* ex = e; ex.Eoper == OPcomma; ex = ex.E2)
                ex.Ety = pea.Ety;
            return e;
        }
    }

    e = el_una(OPaddr, TYnptr, e);
    return e;
}

/********************************
 * Reset stringTab[] between object files being emitted, because the symbols are local.
 */
void clearStringTab()
{
    //printf("clearStringTab()\n");
    if (stringTab)
        stringTab.reset(1000);             // 1000 is arbitrary guess
    else
    {
        stringTab = new StringTable!(Symbol*)();
        stringTab._init(1000);
    }
}
private __gshared StringTable!(Symbol*) *stringTab;

/*********************************************
 * Figure out whether a data symbol should be dllimported
 * Params:
 *      symbl = declaration of the symbol
 * Returns:
 *      true if symbol should be imported from a DLL
 */
bool isDllImported(Dsymbol symbl)
{
    // Windows is the only platform which dmd supports, that uses the DllImport/DllExport scheme.
    if (!(target.os & Target.OS.Windows))
        return false;

    // If function does not have a body, check to see if its marked as DllImport or is set to be exported.
    // If a global variable has both export + extern, it is DllImport
    if (symbl.isImportedSymbol())
        return true;

    // Functions can go through the generated trampoline function.
    // Not efficient, but it works.
    if (symbl.isFuncDeclaration())
        return false; // can always jump through import table

    // Global variables are allowed, but not TLS or read only memory.
    if (auto vd = symbl.isDeclaration())
    {
        if (!vd.isDataseg() || vd.isThreadlocal())
            return false;
    }

    final switch(driverParams.symImport)
    {
        case SymImport.none:
            // If DllImport overriding is disabled, do not change dllimport status.
            return false;

        case SymImport.externalOnly:
            // Only modules that are marked as out of binary will be DllImport
            break;

        case SymImport.defaultLibsOnly:
        case SymImport.all:
            // If to access anything in druntime/phobos you need DllImport, verify against this.
            break;
    }

    // For TypeInfo's check to see if its in druntime and DllImport it
    if (auto tid = symbl.isTypeInfoDeclaration())
    {
        // Built in TypeInfo's are defined in druntime
        if (builtinTypeInfo(tid.tinfo))
            return true;

        // Convert TypeInfo to its symbol
        if (auto ad = isAggregate(tid.type))
            symbl = ad;
    }

    {
        // Filter the symbol based upon the module it is in.

        auto m = symbl.getModule();
        if (!m || !m.md)
            return false;

        if (driverParams.symImport == SymImport.all || m.isExplicitlyOutOfBinary)
        {
            // If a module is specified as being out of binary (-extI), then it is allowed to be DllImport.
        }
        else if (driverParams.symImport == SymImport.externalOnly)
        {
            // Module is in binary, therefore not DllImport
            return false;
        }
        else if (driverParams.symImport == SymImport.defaultLibsOnly)
        {
            // Filter out all modules that are not in druntime/phobos if we are only doing default libs only

            const id = m.md.packages.length ? m.md.packages[0] : null;
            if (id && id != Id.core && id != Id.std)
                return false;
            if (!id && m.md.id != Id.std && m.md.id != Id.object)
                return false;
        }
    }

    // If symbol is a ModuleInfo, check to see if module is being compiled.
    if (auto mod = symbl.isModule())
    {
        const isBeingCompiled = mod.isRoot();
        return !isBeingCompiled; // non-root ModuleInfo symbol
    }

    // Check to see if a template has been instatiated in current compilation,
    //  if it is defined in a external module, its DllImport.
    if (symbl.inNonRoot())
        return true; // not instantiated, and defined in non-root

    // If a template has been instatiated, only DllImport if it is codegen'ing
    if (auto ti = symbl.isInstantiated()) // && !defineOnDeclare(sym, false))
        return !ti.needsCodegen(); // instantiated but potentially culled (needsCodegen())

    // If a variable declaration and is extern
    if (auto vd = symbl.isVarDeclaration())
    {
        // Shouldn't this be including an export check too???
        if (vd.storage_class & STC.extern_)
            return true; // externally defined global variable
    }

    return false;
}

/*********************************************
 * Generate a backend symbol for a frontend symbol
 * Params:
 *      s = frontend symbol
 * Returns:
 *      the backend symbol or the associated symbol in the
 *      import table if it is expected to be imported from a DLL
 */
Symbol* toExtSymbol(Dsymbol s)
{
    if (isDllImported(s))
        return toImport(s);
    else
        return toSymbol(s);
}

private elem* toEfilenamePtr(Module m)
{
    //printf("toEfilenamePtr(%s)\n", m.toChars());
    const(char)* id = m.srcfile.toChars();
    size_t len = strlen(id);
    Symbol* s = toStringSymbol(id, len, 1);
    return el_ptr(s);
}

/*********************************************
 * Convert Expression to backend elem.
 * Params:
 *      e = expression tree
 *      irs = context
 * Returns:
 *      backend elem tree
 */
elem* toElem(Expression e, ref IRState irs)
{
    elem* visit(Expression e)
    {
        printf("[%s] %s: %s\n", e.loc.toChars(), EXPtoString(e.op).ptr, e.toChars());
        assert(0);
    }

    elem* visitSymbol(SymbolExp se) // VarExp and SymOffExp
    {
        elem* e;
        Type tb = (se.op == EXP.symbolOffset) ? se.var.type.toBasetype() : se.type.toBasetype();
        long offset = (se.op == EXP.symbolOffset) ? cast(long)(cast(SymOffExp)se).offset : 0;
        VarDeclaration v = se.var.isVarDeclaration();

        //printf("[%s] SymbolExp.toElem('%s') %p, %s\n", se.loc.toChars(), se.toChars(), se, se.type.toChars());
        //printf("\tparent = '%s'\n", se.var.parent ? se.var.parent.toChars() : "null");
        if (se.op == EXP.variable && se.var.needThis())
        {
            irs.eSink.error(se.loc, "need `this` to access member `%s`", se.toChars());
            return el_long(TYsize_t, 0);
        }

        /* The magic variable __ctfe is always false at runtime
         */
        if (se.op == EXP.variable && v && v.ident == Id.ctfe)
        {
            return el_long(totym(se.type), 0);
        }

        if (FuncLiteralDeclaration fld = se.var.isFuncLiteralDeclaration())
        {
            if (fld.tok == TOK.reserved)
            {
                // change to non-nested
                fld.tok = TOK.function_;
                fld.vthis = null;
            }
            if (!fld.deferToObj)
            {
                fld.deferToObj = true;
                irs.deferToObj.push(fld);
            }
        }

        Symbol* s = toSymbol(se.var);

        // VarExp generated for `__traits(initSymbol, Aggregate)`?
        if (auto symDec = se.var.isSymbolDeclaration())
        {
            if (auto ta = se.type.isTypeDArray())
            {
                // Type must be const(void)[] or const(void[])
                assert(ta.nextOf() == Type.tvoid.constOf(), se.type.toString());

                // Generate s[0 .. Aggregate.sizeof] for non-zero initialised aggregates
                // Otherwise create (null, Aggregate.sizeof)
                auto ad = symDec.dsym;
                auto ptr = (ad.isStructDeclaration() && ad.type.isZeroInit(Loc.initial))
                        ? el_long(TYnptr, 0)
                        : el_ptr(s);
                auto length = el_long(TYsize_t, ad.structsize);
                auto slice = el_pair(TYdarray, length, ptr);
                elem_setLoc(slice, se.loc);
                return slice;
            }
        }

        FuncDeclaration fd = null;
        if (se.var.toParent2())
            fd = se.var.toParent2().isFuncDeclaration();

        const bool nrvo = fd && (fd.isNRVO && fd.nrvo_var == se.var || se.var.nrvo && fd.shidden);
        if (nrvo)
            s = cast(Symbol*)fd.shidden;

        if (s.Sclass == SC.auto_ || s.Sclass == SC.parameter || s.Sclass == SC.shadowreg)
        {
            if (fd && fd != irs.getFunc())
            {
                // 'var' is a variable in an enclosing function.
                elem* ethis = getEthis(se.loc, irs, fd, null, se.originalScope);
                ethis = el_una(OPaddr, TYnptr, ethis);

                /* https://issues.dlang.org/show_bug.cgi?id=9383
                 * If 's' is a virtual function parameter
                 * placed in closure, and actually accessed from in/out
                 * contract, instead look at the original stack data.
                 */
                bool forceStackAccess = false;
                if (fd.isVirtual() && (fd.fdrequire || fd.fdensure))
                {
                    Dsymbol sx = irs.getFunc();
                    while (sx != fd)
                    {
                        if (sx.ident == Id.require || sx.ident == Id.ensure)
                        {
                            forceStackAccess = true;
                            break;
                        }
                        sx = sx.toParent2();
                    }
                }

                int soffset;
                if (v && v.inClosure && !forceStackAccess)
                    soffset = v.offset;
                else if (v && v.inAlignSection)
                {
                    const vthisOffset = fd.vthis ? -toSymbol(fd.vthis).Soffset : 0;
                    auto salignSection = cast(Symbol*) fd.salignSection;
                    ethis = el_bin(OPadd, TYnptr, ethis, el_long(TYnptr, vthisOffset + salignSection.Soffset));
                    ethis = el_una(OPind, TYnptr, ethis);
                    soffset = v.offset;
                }
                else
                {
                    soffset = cast(int)s.Soffset;
                    /* If fd is a non-static member function of a class or struct,
                     * then ethis isn't the frame pointer.
                     * ethis is the 'this' pointer to the class/struct instance.
                     * We must offset it.
                     */
                    if (fd.vthis)
                    {
                        Symbol* vs = toSymbol(fd.vthis);
                        //printf("vs = %s, offset = x%x, %p\n", vs.Sident.ptr, cast(int)vs.Soffset, vs);
                        soffset -= vs.Soffset;
                    }
                    //printf("\tSoffset = x%x, sthis.Soffset = x%x\n", cast(uint)s.Soffset, cast(uint)irs.sthis.Soffset);
                }

                if (!nrvo)
                    soffset += offset;

                e = el_bin(OPadd, TYnptr, ethis, el_long(TYnptr, soffset));
                if (se.op == EXP.variable)
                    e = el_una(OPind, TYnptr, e);
                if ((se.var.isReference() || ISX64REF(se.var)) && !(ISX64REF(se.var) && v && v.offset && !forceStackAccess))
                    e = el_una(OPind, s.Stype.Tty, e);
                else if (se.op == EXP.symbolOffset && nrvo)
                {
                    e = el_una(OPind, TYnptr, e);
                    e = el_bin(OPadd, e.Ety, e, el_long(TYsize_t, offset));
                }
                goto L1;
            }
        }

        /* If var is a member of a closure or aligned section
         */
        if (v && (v.inClosure || v.inAlignSection))
        {
            auto salignSection = cast(Symbol*) fd.salignSection;
            assert(irs.sclosure || salignSection);
            e = el_var(v.inClosure ? irs.sclosure : salignSection);
            e = el_bin(OPadd, TYnptr, e, el_long(TYsize_t, v.offset));
            if (se.op == EXP.variable)
            {
                e = el_una(OPind, totym(se.type), e);
                if (tybasic(e.Ety) == TYstruct)
                    e.ET = Type_toCtype(se.type);
                elem_setLoc(e, se.loc);
            }
            if (se.var.isReference())
            {
                e.Ety = TYnptr;
                e = el_una(OPind, s.Stype.Tty, e);
            }
            else if (se.op == EXP.symbolOffset && nrvo)
            {
                e = el_una(OPind, TYnptr, e);
                e = el_bin(OPadd, e.Ety, e, el_long(TYsize_t, offset));
            }
            else if (se.op == EXP.symbolOffset)
            {
                e = el_bin(OPadd, e.Ety, e, el_long(TYsize_t, offset));
            }
            goto L1;
        }

        if (s.Sclass == SC.auto_ && s.Ssymnum == SYMIDX.max)
        {
            //printf("\tadding symbol %s\n", s.Sident);
            symbol_add(s);
        }

        if (se.op == EXP.variable && isDllImported(se.var))
        {
            assert(se.op == EXP.variable);
            if (target.os & Target.OS.Posix)
            {
                e = el_var(s);
            }
            else
            {
                e = el_var(toImport(se.var));
                e = el_una(OPind,s.Stype.Tty,e);
            }
        }
        else if (se.var.isReference() || ISX64REF(se.var))
        {
            // Out parameters are really references
            e = el_var(s);
            e.Ety = TYnptr;
            if (se.op == EXP.variable)
                e = el_una(OPind, s.Stype.Tty, e);
            else if (offset)
                e = el_bin(OPadd, TYnptr, e, el_long(TYsize_t, offset));
        }
        else if (se.op == EXP.variable)
        {
            if (sytab[s.Sclass] & SCDATA && s.Sfl != FL.func && target.isAArch64)
            {
                /* AArch64 does not have an LEA instruction,
                 * so access data segment data via a pointer
                 */
                e = el_ptr(s);
                e = el_una(OPind,s.Stype.Tty,e); // e = * & s
            }
            else
                e = el_var(s);
        }
        else
        {
            e = nrvo ? el_var(s) : el_ptr(s);
            e = el_bin(OPadd, e.Ety, e, el_long(TYsize_t, offset));
        }
    L1:
        if (se.op != EXP.variable)
        {
            elem_setLoc(e,se.loc);
            return e;
        }

        if (nrvo)
        {
            e.Ety = TYnptr;
            e = el_una(OPind, 0, e);
        }

        tym_t tym;
        if (se.var.storage_class & STC.lazy_)
            tym = TYdelegate;       // Tdelegate as C type
        else if (tb.ty == Tfunction)
            tym = s.Stype.Tty;
        else
            tym = totym(se.type);

        e.Ejty = cast(ubyte)(e.Ety = tym);

        if (tybasic(tym) == TYstruct)
        {
            e.ET = Type_toCtype(se.type);
        }
        else if (tybasic(tym) == TYarray)
        {
            e.Ejty = e.Ety = TYstruct;
            e.ET = Type_toCtype(se.type);
        }
        else if (tysimd(tym))
        {
            e.ET = Type_toCtype(se.type);
        }

        elem_setLoc(e,se.loc);
        return e;
    }

    elem* visitFunc(FuncExp fe)
    {
        //printf("FuncExp.toElem() %s\n", fe.toChars());
        FuncLiteralDeclaration fld = fe.fd;

        if (fld.tok == TOK.reserved && fe.type.ty == Tpointer)
        {
            // change to non-nested
            fld.tok = TOK.function_;
            fld.vthis = null;
        }
        if (!fld.deferToObj)
        {
            fld.deferToObj = true;
            irs.deferToObj.push(fld);
        }

        Symbol* s = toSymbol(fld);
        elem* e = el_ptr(s);
        if (fld.isNested())
        {
            elem* ethis;
            // Delegate literals report isNested() even if they are in global scope,
            // so we need to check that the parent is a function.
            if (!fld.toParent2().isFuncDeclaration())
                ethis = el_long(TYnptr, 0);
            else
                ethis = getEthis(fe.loc, irs, fld);
…49048 tokens truncated…        ec = el_selecte2(ec);           // *
                    }
                }
            }
        }


        if (dctor)
        {
        }
        else if (ce.arguments && ce.arguments.length && ec.Eoper != OPvar)
        {
            if (ec.Eoper == OPind && el_sideeffect(ec.E1))
            {
                /* Rewrite (*exp)(arguments) as:
                 * tmp = exp, (*tmp)(arguments)
                 */
                elem* ec1 = ec.E1;
                Symbol* stmp = symbol_genauto(type_fake(ec1.Ety));
                eeq = el_bin(OPeq, ec.Ety, el_var(stmp), ec1);
                ec.E1 = el_var(stmp);
            }
            else if (tybasic(ec.Ety) != TYnptr)
            {
                /* Rewrite (exp)(arguments) as:
                 * tmp=&exp, (*tmp)(arguments)
                 */
                ec = addressElem(ec, ectype);

                Symbol* stmp = symbol_genauto(type_fake(ec.Ety));
                eeq = el_bin(OPeq, ec.Ety, el_var(stmp), ec);
                ec = el_una(OPind, totym(ectype), el_var(stmp));
            }
        }
    }
    else if (ce.e1.op == EXP.variable)
    {
        fd = (cast(VarExp)ce.e1).var.isFuncDeclaration();
        version (none)
        {
            // This optimization is not valid if alloca can be called
            // multiple times within the same function, eg in a loop
            // see https://issues.dlang.org/show_bug.cgi?id=3822
            if (fd && fd.ident == Id.__alloca &&
                !fd.fbody && fd._linkage == LINK.c &&
                arguments && arguments.length == 1)
            {   Expression arg = (*arguments)[0];
                arg = arg.optimize(WANTvalue);
                if (arg.isConst() && arg.type.isIntegral())
                {   const sz = arg.toInteger();
                    if (sz > 0 && sz < 0x40000)
                    {
                        // It's an alloca(sz) of a fixed amount.
                        // Replace with an array allocated on the stack
                        // of the same size: char[sz] tmp;

                        assert(!ehidden);
                        .type* t = type_static_array(sz, tschar);  // BUG: fix extra Tcount++
                        Symbol* stmp = symbol_genauto(t);
                        ec = el_ptr(stmp);
                        elem_setLoc(ec,loc);
                        return ec;
                    }
                }
            }
        }

        ec = toElem(ce.e1, irs);
    }
    else
    {
        ec = toElem(ce.e1, irs);
        if (ce.arguments && ce.arguments.length)
        {
            /* The idea is to enforce expressions being evaluated left to right,
             * even though call trees are evaluated parameters first.
             * We just do a quick hack to catch the more obvious cases, though
             * we need to solve this generally.
             */
            if (ec.Eoper == OPind && el_sideeffect(ec.E1))
            {
                /* Rewrite (*exp)(arguments) as:
                 * tmp=exp, (*tmp)(arguments)
                 */
                elem* ec1 = ec.E1;
                Symbol* stmp = symbol_genauto(type_fake(ec1.Ety));
                eeq = el_bin(OPeq, ec.Ety, el_var(stmp), ec1);
                ec.E1 = el_var(stmp);
            }
            else if (tybasic(ec.Ety) == TYdelegate && el_sideeffect(ec))
            {
                /* Rewrite (exp)(arguments) as:
                 * tmp=exp, (tmp)(arguments)
                 */
                Symbol* stmp = symbol_genauto(type_fake(ec.Ety));
                eeq = el_bin(OPeq, ec.Ety, el_var(stmp), ec);
                ec = el_var(stmp);
            }
        }
    }
    elem* ethis2 = null;

    // Packed memory intrinsics carry a typed operation through this boundary.
    // The conservative follower emits a single scalar load/store. This is the
    // only place a target-specific follower needs to be added later; semantic
    // details need not be inferred from the resulting elem tree.
    if (fd && isPackedMemoryIntrinsic(fd))
    {
        auto operation = makePackedMemoryOperation(fd, ce, irs);
        if (operation.valid)
            tracePackedMemory(operation);
        elem* lowered = lowerPackedMemory(operation, irs);
        elem_setLoc(lowered, ce.loc);
        if (eeq)
            lowered = el_combine(eeq, lowered);
        return lowered;
    }

    if (ce.vthis2)
    {
        // avoid using toSymbol directly because vthis2 may be a closure var
        Expression ve = new VarExp(ce.loc, ce.vthis2);
        ve.type = ce.vthis2.type;
        ve = new AddrExp(ce.loc, ve);
        ve.type = ce.vthis2.type.pointerTo();
        ethis2 = toElem(ve, irs);
    }
    elem* ecall = callfunc(ce.loc, irs, ce.directcall, ce.type, ec, ectype, fd, t1, ehidden, ce.arguments, null, ethis2);

    if (dctor && ecall.Eoper == OPind)
    {
        /* Continuation of fix outlined above for moving constructor call into dctor tree.
         * Given:
         *   eeq:   (dctor info ((__ctmp = initializer),__ctmp))
         *   eeq:   (dctor info ((_flag=0),((__ctmp = initializer),__ctmp)))   for EH_DWARF
         *   ecall: * call(ce, args)
         * Rewrite ecall as:
         *    * (dctor info ((__ctmp = initializer),call(ce, args)))
         *    * (dctor info ((_flag=0),(__ctmp = initializer),call(ce, args)))
         */
        elem* ea = ecall.E1;           // ea: call(ce,args)
        tym_t ty = ea.Ety;
        ecall.E1 = eeq;
        assert(eeq.Eoper == OPinfo);
        elem* eeqcomma = eeq.E2;
        assert(eeqcomma.Eoper == OPcomma);
        while (eeqcomma.E2.Eoper == OPcomma)
        {
            eeqcomma.Ety = ty;
            eeqcomma = eeqcomma.E2;
        }
        eeq.Ety = ty;
        el_free(eeqcomma.E2);
        eeqcomma.E2 = ea;               // replace ,__ctmp with ,call(ce,args)
        eeqcomma.Ety = ty;
        eeq = null;
    }

    elem_setLoc(ecall, ce.loc);
    if (eeq)
        ecall = el_combine(eeq, ecall);
    return ecall;
}

/*************************************************
 * Params:
 *      op = EXP.assign, EXP.construct, EXP.blit
 *      sym = struct symbol to initialize with the literal. If null, an auto is created
 *      fillHoles = Fill in alignment holes with zero. Set to
 *                  false if allocated by operator new, as the holes are already zeroed.
 * Returns:
 *      generated elem tree with type TYstruct
 */
elem* toElemStructLit(StructLiteralExp sle, ref IRState irs, EXP op, Symbol* sym, bool fillHoles)
{
    //printf("[%s] StructLiteralExp.toElem() %s\n", sle.loc.toChars(), sle.toChars());
    //printf("\tblit = %s, sym = %p fillHoles = %d\n", op == EXP.blit, sym, fillHoles);

    Type forcetype = null;
    if (sle.stype)
    {
        if (TypeEnum te = sle.stype.isTypeEnum())
        {
            // Reinterpret the struct literal as a complex type.
            if (te.sym.isSpecial() &&
                (te.sym.ident == Id.__c_complex_float ||
                 te.sym.ident == Id.__c_complex_double ||
                 te.sym.ident == Id.__c_complex_real))
            {
                forcetype = sle.stype;
            }
        }
    }

    static elem* Lreinterpret(Loc loc, elem* e, Type type)
    {
        elem* ep = el_una(OPind, totym(type), el_una(OPaddr, TYnptr, e));
        elem_setLoc(ep, loc);
        return ep;
    }

    elem* e;
    // struct symbol to initialize with the literal
    Symbol* stmp = sym;

    if (sle.useStaticInit)
    {
        /* Use the struct declaration's init symbol
         */
        e = el_var(toInitializer(sle.sd));
        e.ET = Type_toCtype(sle.sd.type);
        elem_setLoc(e, sle.loc);

        if (!stmp && sle.type.isMutable())
            stmp = symbol_genauto(Type_toCtype(sle.sd.type));

        if (stmp)
        {
            elem* ev = el_var(stmp);
            if (tybasic(ev.Ety) == TYnptr)
                ev = el_una(OPind, e.Ety, ev);
            ev.ET = e.ET;
            e = elAssign(ev, e, null, ev.ET);
            elem_setLoc(e, sle.loc);
        }
        if (forcetype)
            return Lreinterpret(sle.loc, e, forcetype);
        return e;
    }

    if (!stmp)
        stmp = symbol_genauto(Type_toCtype(sle.sd.type));

    /* If a field has explicit initializer (*sle.elements)[i] != null),
     * any other overlapped fields won't have initializer. It's asserted by
     * StructDeclaration.fill() function.
     *
     *  union U { int x; long y; }
     *  U u1 = U(1);        // elements = [`1`, null]
     *  U u2 = {y:2};       // elements = [null, `2`];
     *  U u3 = U(1, 2);     // error
     *  U u4 = {x:1, y:2};  // error
     */
    size_t dim = sle.elements ? sle.elements.length : 0;
    assert(dim <= sle.sd.fields.length);

    if (fillHoles)
    {
        /* Initialize all alignment 'holes' to zero.
         * Do before initializing fields, as the hole filling process
         * can spill over into the fields.
         */
        const size_t structsize = sle.sd.structsize;
        size_t offset = 0;
        //printf("-- %s - fillHoles, structsize = %d\n", sle.toChars(), structsize);
        for (size_t i = 0; i < sle.sd.fields.length && offset < structsize; )
        {
            VarDeclaration v = sle.sd.fields[i];

            /* If the field v has explicit initializer, [offset .. v.offset]
             * is a hole divided by the initializer.
             * However if the field size is zero (e.g. int[0] v;), we can merge
             * the two holes in the front and the back of the field v.
             */
            if (i < dim && (*sle.elements)[i] && v.type.size())
            {
                //if (offset != v.offset) printf("  1 fillHole, %d .. %d\n", offset, v.offset);
                e = el_combine(e, fillHole(stmp, offset, v.offset, structsize));
                offset = cast(uint)(v.offset + v.type.size());
                i++;
                continue;
            }
            if (!v.overlapped)
            {
                i++;
                continue;
            }

            /* AggregateDeclaration.fields holds the fields by the lexical order.
             * This code will minimize each hole sizes. For example:
             *
             *  struct S {
             *    union { uint f1; ushort f2; }   // f1: 0..4,  f2: 0..2
             *    union { uint f3; ulong f4; }    // f3: 8..12, f4: 8..16
             *  }
             *  S s = {f2:x, f3:y};     // filled holes: 2..8 and 12..16
             */
            size_t vend = sle.sd.fields.length;
            size_t holeEnd = structsize;
            size_t offset2 = structsize;
            foreach (j; i + 1 .. vend)
            {
                VarDeclaration vx = sle.sd.fields[j];
                if (!vx.overlapped)
                {
                    vend = j;
                    break;
                }
                if (j < dim && (*sle.elements)[j] && vx.type.size())
                {
                    // Find the lowest end offset of the hole.
                    if (offset <= vx.offset && vx.offset < holeEnd)
                    {
                        holeEnd = vx.offset;
                        offset2 = cast(uint)(vx.offset + vx.type.size());
                    }
                }
            }
            if (holeEnd < structsize)
            {
                //if (offset != holeEnd) printf("  2 fillHole, %d .. %d\n", offset, holeEnd);
                e = el_combine(e, fillHole(stmp, offset, holeEnd, structsize));
                offset = offset2;
                continue;
            }
            i = vend;
        }
        //if (offset != sle.sd.structsize) printf("  3 fillHole, %d .. %d\n", offset, sle.sd.structsize);
        e = el_combine(e, fillHole(stmp, offset, sle.sd.structsize, sle.sd.structsize));
    }

    // CTFE may fill the hidden pointer by NullExp.
    VarDeclaration vbf;
    foreach (i, element; *sle.elements)
    {
        if (!element)
            continue;

        VarDeclaration v = sle.sd.fields[i];
        assert(!v.isThisDeclaration() || element.op == EXP.null_);

        elem* e1;
        if (tybasic(stmp.Stype.Tty) == TYnptr)
        {
            e1 = el_var(stmp);
        }
        else
        {
            e1 = el_ptr(stmp);
        }

        elem* ep = toElem(element, irs);

        Type t1b = v.type.toBasetype();
        Type t2b = element.type.toBasetype();
        if (t1b.ty == Tsarray)
        {
            e1 = el_bin(OPadd, TYnptr, e1, el_long(TYsize_t, v.offset));
            if (t2b.implicitConvTo(t1b))
            {
                elem* esize = el_long(TYsize_t, t1b.size());
                ep = array_toPtr(element.type, ep);
                e1 = el_bin(OPmemcpy, TYnptr, e1, el_param(ep, esize));
            }
            else
            {
                elem* edim = el_long(TYsize_t, t1b.size() / t2b.size());
                e1 = setArray(element, e1, edim, t2b, ep, irs, op == EXP.construct ? EXP.blit : op);
            }
            e = el_combine(e, e1);
            continue;
        }

        const tym_t tym = totym(v.type);
        auto voffset = v.offset;
        uint bitfieldArg;
        uint bitOffset;
        auto bf = v.isBitFieldDeclaration();
        if (bf)
        {
            const szbits = tysize(tym) * 8;
            bitOffset = bf.bitOffset;
            if (bitOffset + bf.fieldWidth > szbits)
            {
                const advance = bitOffset / szbits;
                voffset += advance;
                bitOffset -= advance * 8;
                assert(bitOffset + bf.fieldWidth <= szbits);
            }
            bitfieldArg = bf.fieldWidth * 256 + bitOffset;

            //printf("2bitOffset %u fieldWidth %u bits %u\n", bitOffset, bf.fieldWidth, szbits);
            assert(bitOffset + bf.fieldWidth <= szbits);
        }

        e1 = el_bin(OPadd, TYnptr, e1, el_long(TYsize_t, voffset));
        e1 = el_una(OPind, tym, e1);
        if (tybasic(tym) == TYstruct)
        {
            e1.ET = Type_toCtype(v.type);
            assert(!bf);
        }
        if (bf)
        {
            if (!vbf || vbf.offset + vbf.type.size() <= v.offset)
            {
                /* Initialize entire location the bitfield is in
                 * ep = (ep & ((1 << bf.fieldWidth) - 1)) << bf.bitOffset
                 */
                auto ex = el_bin(OPand, tym, ep, el_long(tym, (1L << bf.fieldWidth) - 1));
                ep = el_bin(OPshl, tym, ex, el_long(tym, bitOffset));
                vbf = v;
            }
            else
            {
                //printf("2bitOffset %u fieldWidth %u bits %u\n", bf.bitOffset, bf.fieldWidth, tysize(e1.Ety) * 8);
                // Insert special bitfield operator
                auto mos = el_long(TYuint, bitfieldArg);
                e1 = el_bin(OPbit, e1.Ety, e1, mos);
            }
        }
        else
            vbf = null;
        e1 = elAssign(e1, ep, v.type, e1.ET);

        e = el_combine(e, e1);
    }

    if (sle.sd.isNested() && dim != sle.sd.fields.length)
    {
        // Initialize the hidden 'this' pointer
        assert(sle.sd.fields.length);

        elem* e1, e2;
        if (tybasic(stmp.Stype.Tty) == TYnptr)
        {
            e1 = el_var(stmp);
        }
        else
        {
            e1 = el_ptr(stmp);
        }
        if (sle.sd.vthis2)
        {
            /* Initialize sd.vthis2:
             *  *(e2 + sd.vthis2.offset) = this1;
             */
            e2 = el_copytree(e1);
            e2 = setEthis(sle.loc, irs, e2, sle.sd, true);
        }
        /* Initialize sd.vthis:
         *  *(e1 + sd.vthis.offset) = this;
         */
        e1 = setEthis(sle.loc, irs, e1, sle.sd);

        e = el_combine(e, e1);
        e = el_combine(e, e2);
    }

    elem* ev = el_var(stmp);
    if (tybasic(ev.Ety) == TYnptr)
        ev = el_una(OPind, totym(sle.sd.type), ev);
    ev.ET = Type_toCtype(sle.sd.type);
    e = el_combine(e, ev);
    elem_setLoc(e, sle.loc);
    if (forcetype)
        return Lreinterpret(sle.loc, e, forcetype);
    return e;
}

/********************************************
 * Append destructors for varsInScope[starti..endi] to er.
 * Params:
 *      irs = context
 *      er = elem to append destructors to
 *      starti = starting index in varsInScope[]
 *      endi = ending index in varsInScope[]
 * Returns:
 *      er with destructors appended
 */

elem* appendDtors(ref IRState irs, elem* er, size_t starti, size_t endi)
{
    //printf("appendDtors(%d .. %d)\n", cast(int)starti, cast(int)endi);

    /* Code gen can be improved by determining if no exceptions can be thrown
     * between the OPdctor and OPddtor, and eliminating the OPdctor and OPddtor.
     */

    /* Build edtors, an expression that calls destructors on all the variables
     * going out of the scope starti..endi
     */
    elem* edtors = null;
    foreach (i; starti .. endi)
    {
        elem* ed = (*irs.varsInScope)[i];
        if (ed)                                 // if not skipped
        {
            //printf("appending dtor\n");
            (*irs.varsInScope)[i] = null;       // so these are skipped by outer scopes
            edtors = el_combine(ed, edtors);    // execute in reverse order
        }
    }

    if (!edtors)
        return er;
    if (irs.target.os == Target.OS.Windows && !irs.target.isX86_64) // Win32
    {
        BlockState* blx = irs.blx;
        nteh_declarvars(blx);
    }

    /* Append edtors to er, while preserving the value of er
     */
    if (tybasic(er.Ety) == TYvoid)
    {
        /* No value to preserve, so simply append
         */
        er = el_combine(er, edtors);
        return er;
    }

    elem **pe;
    for (pe = &er; (*pe).Eoper == OPcomma; pe = &(*pe).E2)
    {
    }
    elem* erx = *pe;

    if (erx.Eoper == OPconst || erx.Eoper == OPrelconst)
    {
        *pe = el_combine(edtors, erx);
    }
    else if (elemIsLvalue(erx))
    {
        /* Lvalue, take a pointer to it
         */
        elem* ep = el_una(OPaddr, TYnptr, erx);
        elem* e = el_same(ep);
        ep = el_combine(ep, edtors);
        ep = el_combine(ep, e);
        e = el_una(OPind, erx.Ety, ep);
        e.ET = erx.ET;
        *pe = e;
    }
    else if (erx.Eoper == OPinfo)
    {
        *pe = el_combine(erx, edtors);
    }
    else
    {
        //printf("el_copytotmp()\n");
        //printf("erx:\n");    elem_print(erx);
        //printf("edtors:\n"); elem_print(edtors);
        elem* e = el_copytotmp(erx);
        erx = el_combine(erx, edtors);
        *pe = el_combine(erx, e);
    }
    return er;
}

/******************************************************
 * Return an elem that is the file, line, and function suitable
 * for insertion into the parameter list.
 */

elem* filelinefunction(ref IRState irs, Loc loc)
{
    const(char)* id = loc.filename;
    size_t len = strlen(id);
    Symbol* si = toStringSymbol(id, len, 1);
    elem* efilename = el_pair(TYdarray, el_long(TYsize_t, len), el_ptr(si));
    if (irs.target.os == Target.OS.Windows && irs.target.isX86_64)
        efilename = addressElem(efilename, Type.tstring, true);

    elem* elinnum = el_long(TYint, loc.linnum);

    const(char)* s = "";
    FuncDeclaration fd = irs.getFunc();
    if (fd)
    {
        s = fd.Dsymbol.toPrettyChars();
    }

    len = strlen(s);
    si = toStringSymbol(s, len, 1);
    elem* efunction = el_pair(TYdarray, el_long(TYsize_t, len), el_ptr(si));
    if (irs.target.os == Target.OS.Windows && irs.target.isX86_64)
        efunction = addressElem(efunction, Type.tstring, true);

    return el_params(efunction, elinnum, efilename, null);
}

/******************************************************
 * Construct elem to run when an array bounds check fails. (Without additional context)
 * Params:
 *      irs = to get function from
 *      loc = to get file/line from
 * Returns:
 *      elem generated
 */
elem* buildRangeError(ref IRState irs, Loc loc)
{
    final switch (irs.params.checkAction)
    {
    case CHECKACTION.C:
        return callCAssert(irs, loc, null, null, "array overflow");
    case CHECKACTION.halt:
        return genHalt(loc);
    case CHECKACTION.context:
    case CHECKACTION.D:
        const efile = irs.locToFileElem(loc);
        return el_bin(OPcall, TYvoid, el_var(getRtlsym(RTLSYM.DARRAYP)), el_params(el_long(TYint, loc.linnum), efile, null));
    }
}

void applyNullDerefErrorCheck(ref elem* e, tym_t type, ref IRState irs, const ref Loc loc)
{
    auto ne = buildNullDerefError(irs, loc);
    auto originale = el_same(e);
    e = el_bin(OPoror, TYvoid, e, ne);
    e = el_bin(OPcomma, type, e, originale);
}

elem* buildNullDerefError(ref IRState irs, const ref Loc loc)
{
    final switch (irs.params.checkAction)
    {
        case CHECKACTION.C:
            return callCAssert(irs, loc, null, null, "null pointer dereference");
        case CHECKACTION.halt:
            return genHalt(loc);
        case CHECKACTION.context:
        case CHECKACTION.D:
            const efile = irs.locToFileElem(loc);
            return el_bin(OPcall, TYvoid, el_var(getRtlsym(RTLSYM.DNULLP)), el_params(el_long(TYint, loc.linnum), efile, null));
    }
}

/******************************************************
 * Construct elem to run when an array slice is created that is out of bounds
 * Params:
 *      irs = to get function from
 *      loc = to get file/line from
 *      lower = lower bound in slice
 *      upper = upper bound in slice
 *      elength = length of array
 * Returns:
 *      elem generated
 */
elem* buildArraySliceError(ref IRState irs, Loc loc, elem* lower, elem* upper, elem* length)
{
    final switch (irs.params.checkAction)
    {
    case CHECKACTION.C:
        return callCAssert(irs, loc, null, null, "array slice out of bounds");
    case CHECKACTION.halt:
        return genHalt(loc);
    case CHECKACTION.context:
    case CHECKACTION.D:
        assert(upper);
        assert(lower);
        assert(length);
        const efile = irs.locToFileElem(loc);
        return el_bin(OPcall, TYvoid, el_var(getRtlsym(RTLSYM.DARRAY_SLICEP)), el_params(length, upper, lower, el_long(TYint, loc.linnum), efile, null));
    }
}

/******************************************************
 * Construct elem to run when an out of bounds array index is accessed
 * Params:
 *      irs = to get function from
 *      loc = to get file/line from
 *      index = index in the array
 *      elength = length of array
 * Returns:
 *      elem generated
 */
elem* buildArrayIndexError(ref IRState irs, Loc loc, elem* index, elem* length)
{
    final switch (irs.params.checkAction)
    {
    case CHECKACTION.C:
        return callCAssert(irs, loc, null, null, "array index out of bounds");
    case CHECKACTION.halt:
        return genHalt(loc);
    case CHECKACTION.context:
    case CHECKACTION.D:
        assert(length);
        const efile = irs.locToFileElem(loc);
        return el_bin(OPcall, TYvoid, el_var(getRtlsym(RTLSYM.DARRAY_INDEXP)), el_params(length, index, el_long(TYint, loc.linnum), efile, null));
    }
}

/// Returns: elem representing a C-string (char*) to the filename
elem* locToFileElem(const ref IRState irs, Loc loc)
{
    elem* efile;

    if (auto fname = loc.filename)
    {
        const len = strlen(fname);
        Symbol* s = toStringSymbol(fname, len, 1);
        efile = el_ptr(s);
    }
    else
        efile = toEfilenamePtr(cast(Module)irs.blx._module);
    return efile;
}

/****************************************
 * Generate call to C's assert failure function.
 * One of exp, emsg, or str must not be null.
 * Params:
 *      irs = context
 *      loc = location to use for assert message
 *      exp = if not null expression to test (not evaluated, but converted to a string)
 *      emsg = if not null then informative message to be computed at run time
 *      str = if not null then informative message string
 * Returns:
 *      generated call
 */
elem* callCAssert(ref IRState irs, Loc loc, Expression exp, Expression emsg, const(char)* str)
{
    //printf("callCAssert.toElem() %s\n", e.toChars());
    Module m = cast(Module)irs.blx._module;
    const(char)* mname = m.srcfile.toChars();

    elem* getFuncName()
    {
        const(char)* id = "";
        FuncDeclaration fd = irs.getFunc();
        if (fd)
            id = fd.toPrettyChars();
        const len = strlen(id);
        Symbol* si = toStringSymbol(id, len, 1);
        return el_ptr(si);
    }

    //printf("filename = '%s'\n", loc.filename);
    //printf("module = '%s'\n", mname);

    /* If the source file name has changed, probably due
     * to a #line directive.
     */
    elem* efilename;
    if (loc.filename && strcmp(loc.filename, mname) != 0)
    {
        const(char)* id = loc.filename;
        size_t len = strlen(id);
        Symbol* si = toStringSymbol(id, len, 1);
        efilename = el_ptr(si);
    }
    else
    {
        efilename = toEfilenamePtr(m);
    }

    elem* elmsg;
    if (emsg)
    {
        // Assuming here that emsg generates a 0 terminated string
        auto e = toElemDtor(emsg, irs);
        elmsg = array_toPtr(Type.tvoid.arrayOf(), e);
    }
    else if (exp)
    {
        // Generate a message out of the assert expression
        const(char)* id = exp.toChars();
        const len = strlen(id);
        Symbol* si = toStringSymbol(id, len, 1);
        elmsg = el_ptr(si);
    }
    else
    {
        assert(str);
        const len = strlen(str);
        Symbol* si = toStringSymbol(str, len, 1);
        elmsg = el_ptr(si);
    }

    auto eline = el_long(TYint, loc.linnum);

    elem* ea;
    if (irs.target.os == Target.OS.OSX)
    {
        // __assert_rtn(func, file, line, msg);
        elem* efunc = getFuncName();
        auto eassert = el_var(getRtlsym(RTLSYM.C__ASSERT_RTN));
        ea = el_bin(OPcall, TYvoid, eassert, el_params(elmsg, eline, efilename, efunc, null));
        return ea;
    }

    Symbol* assertSym;
    elem* params;
    with (TargetC.Runtime) switch (irs.target.c.runtime)
    {
        case Musl:
        case Glibc:
            // __assert_fail(exp, file, line, func);
            assertSym = getRtlsym(RTLSYM.C__ASSERT_FAIL);
            elem* efunc = getFuncName();
            params = el_params(efunc, eline, efilename, elmsg, null);
            break;
        default:
            // [_]_assert(msg, file, line);
            const rtlsym = (irs.target.os == Target.OS.Windows) ? RTLSYM.C_ASSERT : RTLSYM.C__ASSERT;
            assertSym = getRtlsym(rtlsym);
            params = el_params(eline, efilename, elmsg, null);
            break;
    }
    auto eassert = el_var(assertSym);
    ea = el_bin(OPcall, TYvoid, eassert, params);
    return ea;
}

/********************************************
 * Generate HALT instruction.
 * Params:
 *      loc = location to use for debug info
 * Returns:
 *      generated instruction
 */
elem* genHalt(Loc loc)
{
    elem* e = el_calloc();
    e.Ety = TYnoreturn;
    e.Eoper = OPhalt;
    elem_setLoc(e, loc);
    return e;
}

/**************************************************
 * Initialize the dual-context array with the context pointers.
 * Params:
 *      loc = line and file of what line to show usage for
 *      irs = current context to get the second context from
 *      fd = the target function
 *      ethis2 = dual-context array
 *      ethis = the first context, updated
 *      eside = where to store the assignment expressions, updated
 * Returns:
 *      `ethis2` if successful, null otherwise
 */
private
elem* setEthis2(Loc loc, ref IRState irs, FuncDeclaration fd, elem* ethis2, ref elem* ethis, ref elem* eside)
{
    if (!fd.hasDualContext)
        return null;

    assert(ethis2 && ethis);

    elem* ectx0 = el_una(OPind, ethis.Ety, el_copytree(ethis2));
    elem* eeq0 = el_bin(OPeq, ethis.Ety, ectx0, ethis);
    ethis = el_copytree(ectx0);
    eside = el_combine(eeq0, eside);

    elem* ethis1 = getEthis(loc, irs, fd, fd.toParent2());
    elem* ectx1 = el_bin(OPadd, TYnptr, el_copytree(ethis2), el_long(TYsize_t, tysize(TYnptr)));
    ectx1 = el_una(OPind, TYnptr, ectx1);
    elem* eeq1 = el_bin(OPeq, ethis1.Ety, ectx1, ethis1);
    eside = el_combine(eeq1, eside);

    return ethis2;
}

/*******************************
 * Construct OPva_start elem by rewriting OPparam elem
 * Params:
 *      e = function parameters to va_start()
 * Returns:
 *      OPva_start elem
 */
private
elem* constructVa_start(elem* e)
{
    assert(e.Eoper == OPparam);

    e.Eoper = OPva_start;
    e.Ety = TYvoid;
    if (target.isX86_64 || target.isAArch64)
    {
        // (OPparam &va &arg)
        // call as (OPva_start &va)
    }
    else if (target.isX86) // 32 bit
    {
        // (OPparam &arg &va)  note arguments are swapped from 64 bit path
        // call as (OPva_start &va)
        auto earg = e.E1;
        e.E1 = e.E2;
        e.E2 = earg;
    }
    else
        assert(0);
    return e;
}

/******************************************
 * If argument to a function should use OPstrpar,
 * fix it so it does and return it.
 * Params:
 *      e = argument to be passed to a function
 * Returns:
 *      `e` or `e` converted to an OPstrpar
 */
private
elem* useOPstrpar(elem* e)
{
    tym_t ty = tybasic(e.Ety);
    if (ty == TYstruct || ty == TYarray)
    {
        e = el_una(OPstrpar, TYstruct, e);
        e.ET = e.E1.ET;
        assert(e.ET);
    }
    return e;
}

/********
 * If type is a composite and is to be passed by reference instead of by value
 * Params:
 *      target = target instruction set
 *      t = type
 * Returns:
 *      true if passed by reference
 * Reference:
 *      Procedure Call Standard for the Arm 64-bi Architecture (AArch64) pg 23 B.4
 *      "If the argument type is a Composite Type that is larger than 16 bytes, then the
 *      argument is copied to memory allocated by the caller and the argument is replaced
 *      by a pointer to the copy."
 */
private bool passTypeByRef(ref const Target target, Type t)
{
    return (target.isAArch64 && t.size(Loc.initial) > 16);
}
