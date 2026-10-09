/**
 * Typed DMD AST -> ARMv7-A A32 code.
 *
 * This is the first A32 lowering slice. It uses DMD's parser and semantic
 * passes, follows AAPCS32 base PCS for scalar arguments with C or D linkage,
 * and emits A32 instructions only. Unsupported constructs fail closed.
 *
 * License: Boost License 1.0
 */
module dmd.glue.arm32;

import dmd.astenums : TY, STC, LINK, VarArg, FileType;
import dmd.arraytypes : Dsymbols;
import dmd.common.outbuffer : OutBuffer;
import dmd.typesem : toBasetype;
import dmd.backend.arm32;
import dmd.declaration;
import dmd.dmodule;
import dmd.dsymbol;
import dmd.dsymbolsem : include;
import dmd.errors : error;
import dmd.expression;
import dmd.func;
import dmd.init;
import dmd.location;
import dmd.mangle : mangleExact, mangleToBuffer;
import dmd.mtype;
import dmd.globals : global;
import dmd.root.string : toDString;
import dmd.statement;
import dmd.tokens : EXP;
import std.file : write, exists, remove, mkdirRecurse, rename;
import std.path : dirName;

private class UnsupportedArm32 : Exception
{
    Loc location;
    this(Loc location, string message)
    {
        super(message);
        this.location = location;
    }
}

private void reject(Loc loc, string message)
{
    throw new UnsupportedArm32(loc, message);
}

private void word(ref ubyte[] bytes, uint value)
{
    foreach (i; 0 .. 4)
        bytes ~= cast(ubyte)(value >> (i * 8));
}

private Arm32Global scalarGlobal(string name, ulong value, uint size, uint alignment, bool defined)
{
    assert(size == 1 || size == 4 || size == 8);
    ubyte[] data;
    if (defined)
        foreach (i; 0 .. size)
            data ~= cast(ubyte)(value >> (i * 8));
    return Arm32Global(name, data, defined ? size : 0, alignment, defined);
}

private string moduleInfoSymbol(Module module_)
{
    OutBuffer mangledModule;
    mangleToBuffer(module_, mangledModule);
    return "_D" ~ mangledModule[].idup ~ "12__ModuleInfoZ";
}

private Arm32Global standaloneModuleInfo(Module module_)
{
    enum MIstandalone = 0x4;
    enum MIname = 0x1000;

    ubyte[] data;
    word(data, MIstandalone | MIname);
    word(data, 0); // druntime assigns _index after discovery through minfo
    data ~= cast(const(ubyte)[])module_.toPrettyChars().toDString;
    data ~= 0;
    return Arm32Global(moduleInfoSymbol(module_), data, cast(uint)data.length, 4, true);
}

private bool wordType(Type t)
{
    if (!t)
        return false;
    const ty = t.toBasetype().ty;
    return ty == TY.Tint32 || ty == TY.Tuns32 || ty == TY.Tfloat32 ||
           ty == TY.Tbool || ty == TY.Tpointer;
}

private bool floating(Type t)
{
    return t && t.toBasetype().ty == TY.Tfloat32;
}

private bool vectorFloat4(Type t)
{
    if (!t)
        return false;
    auto vector = t.toBasetype().isTypeVector();
    if (!vector)
        return false;
    auto array = vector.basetype.toBasetype().isTypeSArray();
    auto dim = array ? array.dim.isIntegerExp() : null;
    return dim && dim.getInteger() == 4 &&
           vector.elementType().ty == TY.Tfloat32;
}

private bool pairType(Type t)
{
    if (!t)
        return false;
    const ty = t.toBasetype().ty;
    return ty == TY.Tint64 || ty == TY.Tuns64 || ty == TY.Tfloat64;
}

private uint scalarWords(Type t)
{
    if (wordType(t))
        return 1;
    if (pairType(t))
        return 2;
    return 0;
}

// ABI registers and local homes use words; pointed-to objects and ELF data
// retain their language storage width. In particular, bool occupies one byte.
private uint scalarBytes(Type t)
{
    if (t && t.toBasetype().ty == TY.Tbool)
        return 1;
    return scalarWords(t) * 4;
}

private uint valueWords(Type t)
{
    if (vectorFloat4(t))
        return 4;
    return scalarWords(t);
}

private string declarationName(Declaration declaration, Loc loc)
{
    string name = declaration.mangleOverride.length ? declaration.mangleOverride.idup :
                  declaration.ident.toString().idup;
    foreach (i, ch; name)
    {
        if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' ||
              (i > 0 && ch >= '0' && ch <= '9')))
            reject(loc, "ELF symbol must be a nonempty ASCII C identifier");
    }
    if (!name.length)
        reject(loc, "empty A32 symbol");
    return name;
}

private string functionName(FuncDeclaration function_, Loc loc)
{
    if (function_.resolvedLinkage() == LINK.c)
        return declarationName(function_, loc);

    // mangleToBuffer(FuncDeclaration) may describe an overload set rather
    // than the resolved function. Use the same exact mangler as tocsym,
    // including pragma(mangle) and Unicode identifiers. ELF stores these
    // names as bytes; DMD semantic analysis rejects embedded nulls.
    const name = mangleExact(function_).toDString();
    if (!name.length)
        reject(loc, "empty A32 function symbol");
    return name.idup;
}

private struct LeafEmitter
{
    Arm32Code code;
    Arm32Relocation[] relocations;
    struct Home
    {
        VarDeclaration variable;
        uint slot;
    }
    Home[] homes;
    uint slots;
    size_t[] returns;

    struct GlobalLiteral
    {
        size_t loadAt;
        string symbol;
    }
    GlobalLiteral[] globalLiterals;
    uint[] dataOffsets;

    struct StackParameterLoad
    {
        size_t at;
        uint incomingOffset;
        uint reg;
    }

    struct ArgumentLocation
    {
        uint words;
        int reg = -1;
        uint stackWord;
    }
    StackParameterLoad[] stackParameterLoads;

    struct LoopEdges
    {
        size_t[] breaks;
        size_t[] continues;
    }
    LoopEdges[] loops;

    Loc location;
    uint depth;

    uint temporaryWords(uint words)
    {
        if (words == 2 && (slots & 1))
            ++slots;
        if (!words || slots + words > 126)
            reject(location, "A32 scalar frame exceeds 504 bytes");
        const first = slots;
        slots += words;
        return first;
    }

    uint temporary()
    {
        return temporaryWords(1);
    }

    uint temporary(Type type)
    {
        const words = valueWords(type);
        if (!words)
            reject(location, "A32 temporary requires a supported scalar or float4 vector type");
        return temporaryWords(words);
    }

    bool hasHome(VarDeclaration variable)
    {
        foreach (ref entry; homes)
            if (entry.variable is variable)
                return true;
        return false;
    }

    uint home(VarDeclaration variable)
    {
        foreach (ref entry; homes)
            if (entry.variable is variable)
                return entry.slot;
        reject(variable.loc, "global, captured, or uninitialised variable is outside the initial A32 slice");
        assert(0);
    }

    void bindHome(VarDeclaration variable, uint slot)
    {
        if (hasHome(variable))
            reject(variable.loc, "duplicate A32 variable home");
        homes ~= Home(variable, slot);
    }

    void requireWord(Type t, Loc loc)
    {
        if (!wordType(t))
            reject(loc, "operation currently requires a one-word scalar");
    }

    void requireScalar(Type t, Loc loc)
    {
        if (!scalarWords(t))
            reject(loc, "A32 scalar lowering supports int/uint/bool/pointers, float, long/ulong and double");
    }

    void requireValue(Type t, Loc loc)
    {
        if (!valueWords(t))
            reject(loc, "A32 lowering supports the scalar subset plus 16-byte float4 vectors");
    }

    TypeFunction scalarFunction(FuncDeclaration function_, Loc loc)
    {
        if (function_.isStaticCtorDeclaration() || function_.isStaticDtorDeclaration())
            reject(loc, "A32 module constructor/destructor lifecycle entries are not implemented");
        if (function_.isUnitTestDeclaration())
            reject(loc, "A32 unittest registration is not implemented");

        const linkage = function_.resolvedLinkage();
        const parent = function_.toParent();
        if ((linkage != LINK.c && linkage != LINK.d) ||
            !parent || !parent.isModule() || function_.isNested() ||
            function_.isMember() || function_.needThis() || function_.hasDualContext ||
            function_.vthis || function_.requiresClosure)
            reject(loc, "A32 scalar functions require top-level extern(C) or extern(D) linkage without a hidden context");

        // _Dmain uses druntime's entry convention rather than a general D
        // scalar function's convention. Do not admit it just by mangling it.
        if (function_.isMain())
            reject(loc, "ordinary-D main requires runtime startup not implemented by the A32 scalar slice");
        if (function_.isCrtCtor || function_.isCrtDtor)
            reject(loc, "A32 crt_constructor/crt_destructor lifecycle entries are not implemented");

        auto signature = function_.type.toTypeFunction();
        if (signature.parameterList.varargs != VarArg.none || signature.isRef)
            reject(loc, "variadic or ref-return functions are not implemented");
        if (signature.next.toBasetype().ty != TY.Tvoid)
            requireScalar(signature.next, loc);
        if (signature.parameterList.length > 64)
            reject(loc, "more than 64 scalar parameters are outside the qualification range");

        // Declaration-only imported callees need not have semantic3's
        // VarDeclarations in function_.parameters. Check their actual formal
        // parameter list before accepting any call or definition.
        foreach (i, parameter; signature.parameterList)
        {
            if (parameter.storageClass & (STC.ref_ | STC.out_ | STC.lazy_))
                reject(loc, "ref/out/lazy parameters are not implemented");
            requireScalar(parameter.type, loc);
        }
        return signature;
    }

    void loadValue(Type type, uint slot, uint reg = 0)
    {
        if (vectorFloat4(type))
        {
            if (reg)
                reject(location, "float4 stack loads use q0, not a core-register selector");
            code.stackAddress(slot * 4);
            code.neonLoadF32x4(0, 12);
        }
        else if (scalarWords(type) == 2)
            code.loadPair(slot, reg);
        else
            code.load(slot, reg);
    }

    void storeValue(Type type, uint slot, uint reg = 0)
    {
        if (vectorFloat4(type))
        {
            if (reg)
                reject(location, "float4 stack stores use q0, not a core-register selector");
            code.stackAddress(slot * 4);
            code.neonStoreF32x4(0, 12);
        }
        else if (scalarWords(type) == 2)
            code.storePair(slot, reg);
        else
            code.store(slot, reg);
    }

    // The address arrives in r0. A pair load must preserve it until both
    // words have been read; the result uses r0:r1 under the base PCS.
    void loadMemory(Type type, Loc loc)
    {
        requireValue(type, loc);
        if (vectorFloat4(type))
            code.neonLoadF32x4(0, 0);
        else if (scalarBytes(type) == 1)
            code.instruction(0xE5D00000); // LDRB r0,[r0]
        else if (scalarWords(type) == 2)
        {
            code.instruction(0xE1A02000); // MOV r2,r0
            code.instruction(0xE5920000); // LDR r0,[r2]
            code.instruction(0xE5921004); // LDR r1,[r2,#4]
        }
        else
            code.instruction(0xE5900000); // LDR r0,[r0]
    }

    string globalName(VarDeclaration variable)
    {
        requireScalar(variable.type, variable.loc);
        if (!variable.isDataseg() || variable.isThreadlocal())
            reject(variable.loc, "A32 scalar globals must be non-TLS data-segment variables");
        if (variable.resolvedLinkage() != LINK.c)
            reject(variable.loc, "A32 scalar globals currently require extern(C) linkage");
        return declarationName(variable, variable.loc);
    }

    void globalAddress(VarDeclaration variable)
    {
        const loadAt = code.loadLiteral();
        code.instruction(0xE79F0000); // LDR r0,[pc,r0] through GOT
        globalLiterals ~= GlobalLiteral(loadAt, globalName(variable));
    }

    void condition(Expression expression_)
    {
        requireScalar(expression_.type, expression_.loc);
        expression(expression_);
        if (scalarWords(expression_.type) == 2)
        {
            if (expression_.type.toBasetype().ty == TY.Tfloat64)
                code.instruction(0xE3C11102); // BIC r1,r1,#0x80000000: ignore double sign zero
            code.instruction(0xE1800001);     // ORR r0,r0,r1
        }
        else if (floating(expression_.type))
            code.instruction(0xE1A00080); // MOV r0,r0,LSL #1: +0/-0 -> 0, NaN stays nonzero
        code.instruction(0xE3500000);     // CMP r0,#0
    }

    void address(Expression expression_)
    {
        if (auto variable = expression_.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration)
                reject(expression_.loc, "address target is not a variable");
            if (hasHome(declaration))
                reject(expression_.loc, "taking the address of an A32 stack local is not implemented");
            globalAddress(declaration);
            return;
        }
        if (auto index = expression_.isIndexExp())
        {
            if (index.e1.type.toBasetype().ty != TY.Tpointer ||
                !scalarWords(index.type))
                reject(index.loc, "only caller-owned scalar pointer elements are supported");
            requireWord(index.e2.type, index.loc);
            expression(index.e1);
            const saved = temporary();
            code.store(saved);
            expression(index.e2);
            code.instruction(0xE1A01000); // MOV r1,r0
            const size = scalarBytes(index.type);
            if (size == 4)
                code.instruction(0xE1A01101); // MOV r1,r1,LSL #2
            else if (size == 8)
                code.instruction(0xE1A01181); // MOV r1,r1,LSL #3
            code.load(saved);
            code.instruction(0xE0800001); // ADD r0,r0,r1
            return;
        }
        if (expression_.op == EXP.star)
        {
            requireValue(expression_.type, expression_.loc);
            expression(expression_.isUnaExp().e1);
            return;
        }
        reject(expression_.loc, "unsupported address expression in A32 slice");
    }

    void assign(Expression destination)
    {
        if (auto variable = destination.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration)
                reject(destination.loc, "assignment target is not a variable");
            if (hasHome(declaration))
            {
                storeValue(declaration.type, home(declaration));
                return;
            }
        }

        // Destination evaluation can call a function and overwrite every
        // caller-saved register. Save the complete RHS, then restore the
        // complete assignment result after computing the address once.
        requireValue(destination.type, destination.loc);
        const saved = temporary(destination.type);
        storeValue(destination.type, saved);
        address(destination);
        if (vectorFloat4(destination.type))
        {
            loadValue(destination.type, saved);
            code.neonStoreF32x4(0, 0);
        }
        else if (scalarWords(destination.type) == 2)
        {
            code.instruction(0xE1A02000); // MOV r2,r0: preserve destination address
            code.loadPair(saved, 0);
            code.instruction(0xE5820000); // STR r0,[r2]
            code.instruction(0xE5821004); // STR r1,[r2,#4]
        }
        else
        {
            code.load(saved, 1);
            code.instruction(scalarBytes(destination.type) == 1 ?
                             0xE5C01000 : 0xE5801000); // STRB/STR r1,[r0]
            code.instruction(0xE1A00001); // MOV r0,r1
        }
    }

    void declare(VarDeclaration variable)
    {
        requireValue(variable.type, variable.loc);
        if (variable.storage_class & (STC.static_ | STC.ref_ | STC.out_ | STC.lazy_))
            reject(variable.loc, "static and by-reference locals are outside the A32 value slice");
        bindHome(variable, temporary(variable.type));
        auto initializer = variable._init ? variable._init.isExpInitializer() : null;
        if (!initializer)
            reject(variable.loc, "local requires an expression initializer");
        expression(initializer.exp);
        storeValue(variable.type, home(variable));
    }

    void directCall(CallExp call)
    {
        auto callee = call.f ? call.f.toAliasFunc() : null;
        if (!callee)
            reject(call.loc, "indirect/function-pointer calls are not implemented");
        auto signature = scalarFunction(callee, call.loc);

        const count = call.arguments ? cast(uint)call.arguments.length : 0U;
        if (count != signature.parameterList.length)
            reject(call.loc, "A32 scalar call argument count does not match its formal parameters");

        if (callee.parameters)
        {
            foreach (parameter; *callee.parameters)
                if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                    reject(call.loc, "ref/out/lazy call parameters are not implemented");
        }

        uint[] argumentHomes;
        uint[] argumentWords;
        ArgumentLocation[] locations;
        argumentHomes.length = count;
        argumentWords.length = count;
        locations.length = count;

        if (call.arguments)
        {
            // D requires left-to-right argument evaluation. Stage every
            // value before assigning ABI registers/stack words so a later
            // argument's call cannot clobber an earlier argument's value.
            foreach (i, argument; *call.arguments)
            {
                requireScalar(argument.type, argument.loc);
                expression(argument);
                argumentWords[i] = scalarWords(argument.type);
                argumentHomes[i] = temporary(argument.type);
                storeValue(argument.type, argumentHomes[i]);
            }
        }

        uint ncrn;
        uint stackWords;
        foreach (i; 0 .. count)
        {
            const words = argumentWords[i];
            if (words == 2 && (ncrn & 1))
                ++ncrn; // AAPCS32 C.3: double-word values start in an even core register.

            locations[i].words = words;
            if (ncrn < 4 && words <= 4 - ncrn)
            {
                locations[i].reg = cast(int)ncrn;
                ncrn += words;
            }
            else
            {
                ncrn = 4;
                if (words == 2 && (stackWords & 1))
                    ++stackWords; // AAPCS32 C.7: double-word stack arguments are 8-byte aligned.
                locations[i].stackWord = stackWords;
                stackWords += words;
            }
        }

        const outgoing = (stackWords * 4 + 7) & ~7U;
        code.adjustStack(outgoing, true);

        foreach (i; 0 .. count)
        {
            const source = outgoing + argumentHomes[i] * 4;
            auto loc = locations[i];
            if (loc.reg >= 0)
                continue;
            if (loc.words == 1)
            {
                code.loadStackOffset(source, 0);
                code.storeStackOffset(loc.stackWord * 4, 0);
            }
            else
            {
                code.loadStackOffset(source, 0);
                code.loadStackOffset(source + 4, 1);
                code.storeStackOffset(loc.stackWord * 4, 0);
                code.storeStackOffset(loc.stackWord * 4 + 4, 1);
            }
        }

        foreach (i; 0 .. count)
        {
            auto loc = locations[i];
            if (loc.reg < 0)
                continue;
            const source = outgoing + argumentHomes[i] * 4;
            const reg = cast(uint)loc.reg;
            code.loadStackOffset(source, reg);
            if (loc.words == 2)
                code.loadStackOffset(source + 4, reg + 1);
        }

        const at = code.call();
        relocations ~= Arm32Relocation(cast(uint)at, functionName(callee, call.loc), ARM32_R_CALL);
        code.adjustStack(outgoing, false);
    }

    void pairShift(Expression e, BinExp binary)
    {
        if (scalarWords(binary.e1.type) != 2 || scalarWords(binary.e2.type) != 1)
            reject(e.loc, "A32 64-bit shift requires a two-word value and one-word count");
        const valueTy = binary.e1.type.toBasetype().ty;
        if (valueTy != TY.Tint64 && valueTy != TY.Tuns64)
            reject(e.loc, "A32 64-bit shifts currently require long/ulong");

        expression(binary.e1);
        const saved = temporary(binary.e1.type);
        code.storePair(saved, 0);
        expression(binary.e2);
        code.instruction(0xE1A02000); // MOV r2,r0: EABI shift count
        code.loadPair(saved, 0);

        string helper;
        switch (e.op)
        {
            case EXP.leftShift:
                helper = "__aeabi_llsl";
                break;
            case EXP.unsignedRightShift:
                helper = "__aeabi_llsr";
                break;
            case EXP.rightShift:
                helper = valueTy == TY.Tuns64 ? "__aeabi_llsr" : "__aeabi_lasr";
                break;
            default:
                reject(e.loc, "unsupported A32 64-bit shift operation");
        }
        const at = code.call();
        relocations ~= Arm32Relocation(cast(uint)at, helper, ARM32_R_CALL);
    }

    void pairBinary(Expression e, BinExp binary)
    {
        requireScalar(binary.e1.type, binary.e1.loc);
        requireScalar(binary.e2.type, binary.e2.loc);
        if (scalarWords(binary.e1.type) != 2 || scalarWords(binary.e2.type) != 2)
            reject(e.loc, "mixed one/two-word binary operation is not implemented");

        expression(binary.e1);
        const saved = temporary(binary.e1.type);
        code.storePair(saved, 0);
        expression(binary.e2);
        code.instruction(0xE1A02000); // MOV r2,r0
        code.instruction(0xE1A03001); // MOV r3,r1
        code.loadPair(saved, 0);

        const ty = binary.e1.type.toBasetype().ty;
        const fp64 = ty == TY.Tfloat64;
        const unsigned64 = ty == TY.Tuns64;

        if (fp64)
        {
            code.instruction(0xEC410B10); // VMOV d0,r0,r1
            code.instruction(0xEC432B11); // VMOV d1,r2,r3
            switch (e.op)
            {
                case EXP.add: code.instruction(0xEE300B01); break;
                case EXP.min: code.instruction(0xEE300B41); break;
                case EXP.mul: code.instruction(0xEE200B01); break;
                case EXP.div: code.instruction(0xEE800B01); break;
                case EXP.equal: case EXP.notEqual:
                case EXP.lessThan: case EXP.lessOrEqual:
                case EXP.greaterThan: case EXP.greaterOrEqual:
                {
                    code.instruction(0xEEB40B41); // VCMP.F64 d0,d1
                    code.instruction(0xEEF1FA10); // VMRS APSR_nzcv,FPSCR
                    uint cc;
                    switch (e.op)
                    {
                        case EXP.equal:          cc = 0; break;
                        case EXP.notEqual:       cc = 1; break;
                        case EXP.lessThan:       cc = 4; break;
                        case EXP.lessOrEqual:    cc = 9; break;
                        case EXP.greaterThan:    cc = 12; break;
                        case EXP.greaterOrEqual: cc = 10; break;
                        default: assert(0);
                    }
                    code.booleanResult(cc);
                    return;
                }
                default:
                    reject(e.loc, "unsupported double binary operation in A32 slice");
            }
            code.instruction(0xEC510B10); // VMOV r0,r1,d0
            return;
        }

        switch (e.op)
        {
            case EXP.add:
                code.instruction(0xE0900002); // ADDS r0,r0,r2
                code.instruction(0xE0A11003); // ADC r1,r1,r3
                return;
            case EXP.min:
                code.instruction(0xE0500002); // SUBS r0,r0,r2
                code.instruction(0xE0C11003); // SBC r1,r1,r3
                return;
            case EXP.mul:
                code.instruction(0xE08EC092); // UMULL r12,lr,r2,r0
                code.instruction(0xE021E192); // MLA r1,r2,r1,lr
                code.instruction(0xE0211093); // MLA r1,r3,r0,r1
                code.instruction(0xE1A0000C); // MOV r0,r12
                return;
            case EXP.div:
            case EXP.mod:
            {
                const helper = unsigned64 ? "__aeabi_uldivmod" : "__aeabi_ldivmod";
                const at = code.call();
                relocations ~= Arm32Relocation(cast(uint)at, helper, ARM32_R_CALL);
                if (e.op == EXP.mod)
                {
                    code.instruction(0xE1A00002); // MOV r0,r2
                    code.instruction(0xE1A01003); // MOV r1,r3
                }
                return;
            }
            case EXP.and:
                code.instruction(0xE0000002); // AND r0,r0,r2
                code.instruction(0xE0011003); // AND r1,r1,r3
                return;
            case EXP.or:
                code.instruction(0xE1800002); // ORR r0,r0,r2
                code.instruction(0xE1811003); // ORR r1,r1,r3
                return;
            case EXP.xor:
                code.instruction(0xE0200002); // EOR r0,r0,r2
                code.instruction(0xE0211003); // EOR r1,r1,r3
                return;
            case EXP.equal:
            case EXP.notEqual:
            {
                code.instruction(0xE0200002); // EOR r0,r0,r2
                code.instruction(0xE0211003); // EOR r1,r1,r3
                code.instruction(0xE1800001); // ORR r0,r0,r1
                code.instruction(0xE3500000); // CMP r0,#0
                code.booleanResult(e.op == EXP.equal ? 0 : 1);
                return;
            }
            case EXP.lessThan:
            case EXP.lessOrEqual:
            case EXP.greaterThan:
            case EXP.greaterOrEqual:
            {
                // Compare high words first. If they are equal, the low words
                // are always compared as unsigned. This preserves whole-value
                // equality for strict unsigned conditions such as HI.
                code.instruction(0xE1510003); // CMP r1,r3
                auto highDiff = code.conditional(1); // BNE
                code.instruction(0xE1500002); // CMP r0,r2
                uint lowCc;
                switch (e.op)
                {
                    case EXP.lessThan:       lowCc = 3; break; // LO
                    case EXP.lessOrEqual:    lowCc = 9; break; // LS
                    case EXP.greaterThan:    lowCc = 8; break; // HI
                    case EXP.greaterOrEqual: lowCc = 2; break; // HS
                    default: assert(0);
                }
                code.booleanResult(lowCc);
                auto done = code.branch();

                code.resolve(highDiff, code.bytes.length);
                uint highCc;
                switch (e.op)
                {
                    case EXP.lessThan:       highCc = unsigned64 ? 3 : 11; break;
                    case EXP.lessOrEqual:    highCc = unsigned64 ? 3 : 11; break;
                    case EXP.greaterThan:    highCc = unsigned64 ? 8 : 12; break;
                    case EXP.greaterOrEqual: highCc = unsigned64 ? 8 : 12; break;
                    default: assert(0);
                }
                code.booleanResult(highCc);
                code.resolve(done, code.bytes.length);
                return;
            }
            default:
                reject(e.loc, "unsupported 64-bit integer binary operation in A32 slice");
        }
    }

    void expression(Expression e)
    {
        if (!e)
            return;
        if (++depth > 128)
            reject(e.loc, "A32 expression nesting exceeds 128");
        scope(exit) --depth;

        if (e.type && e.type.toBasetype().ty != TY.Tvoid && e.op != EXP.declaration)
            requireValue(e.type, e.loc);

        if (auto integer = e.isIntegerExp())
        {
            if (pairType(e.type))
                code.constant64(cast(ulong)integer.value);
            else
                code.constant(cast(uint)integer.value);
            return;
        }
        if (auto realConstant = e.isRealExp())
        {
            if (floating(e.type))
            {
                union Payload32
                {
                    float value;
                    uint bits;
                }
                Payload32 payload;
                payload.value = cast(float)realConstant.value;
                code.constant(payload.bits);
                return;
            }
            if (e.type.toBasetype().ty == TY.Tfloat64)
            {
                union Payload64
                {
                    double value;
                    ulong bits;
                }
                Payload64 payload;
                payload.value = cast(double)realConstant.value;
                code.constant64(payload.bits);
                return;
            }
            reject(e.loc, "floating constant is outside the float/double A32 scalar subset");
        }
        if (e.op == EXP.null_)
        {
            code.constant(0);
            return;
        }
        if (auto symbolOffset = e.isSymOffExp())
        {
            auto declaration = symbolOffset.var.isVarDeclaration();
            if (!declaration)
                reject(e.loc, "A32 symbol-offset expressions currently support data symbols only");
            if (symbolOffset.offset != 0)
                reject(e.loc, "nonzero A32 data symbol offsets are not implemented yet");
            globalAddress(declaration);
            return;
        }
        if (auto variable = e.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration)
                reject(e.loc, "function values are outside the initial A32 slice");
            if (hasHome(declaration))
                loadValue(declaration.type, home(declaration));
            else
            {
                if (vectorFloat4(declaration.type))
                    reject(e.loc, "A32 float4 globals are not implemented");
                globalAddress(declaration);
                loadMemory(declaration.type, e.loc);
            }
            return;
        }
        if (auto declaration = e.isDeclarationExp())
        {
            auto variable = declaration.declaration.isVarDeclaration();
            if (!variable)
                reject(e.loc, "only local value declarations are implemented");
            declare(variable);
            return;
        }
        if (auto cast_ = e.isCastExp())
        {
            if (cast_.type.toBasetype().ty == TY.Tbool)
            {
                condition(cast_.e1);
                code.booleanResult(1); // NE
                return;
            }
            const sourceWords = scalarWords(cast_.e1.type);
            const targetWords = scalarWords(cast_.type);
            if (sourceWords == 2 || targetWords == 2)
            {
                const sourceTy = cast_.e1.type.toBasetype().ty;
                const targetTy = cast_.type.toBasetype().ty;
                const sourceIntegerWord =
                    sourceTy == TY.Tint32 || sourceTy == TY.Tuns32 ||
                    sourceTy == TY.Tbool || sourceTy == TY.Tpointer;
                const targetIntegerWord =
                    targetTy == TY.Tint32 || targetTy == TY.Tuns32 ||
                    targetTy == TY.Tbool || targetTy == TY.Tpointer;
                const sourceIntegerPair = sourceTy == TY.Tint64 || sourceTy == TY.Tuns64;
                const targetIntegerPair = targetTy == TY.Tint64 || targetTy == TY.Tuns64;

                if (sourceWords == 1 && targetIntegerPair && sourceIntegerWord)
                {
                    expression(cast_.e1);
                    if (sourceTy == TY.Tint32)
                        code.instruction(0xE1A01FC0); // ASR r1,r0,#31: sign extend
                    else
                        code.instruction(0xE3A01000); // MOV r1,#0: zero extend
                    return;
                }
                if (targetWords == 1 && sourceIntegerPair && targetIntegerWord)
                {
                    expression(cast_.e1); // truncate: low word is already r0
                    return;
                }
                if (sourceWords == 2 && targetWords == 2 &&
                    ((sourceIntegerPair && targetIntegerPair) || sourceTy == targetTy))
                {
                    expression(cast_.e1);
                    return;
                }
                reject(e.loc, "conversion is outside the qualified A32 integer-width scalar subset");
            }
            if (floating(cast_.type) != floating(cast_.e1.type))
                reject(e.loc, "integer/float conversions are not implemented");
            requireWord(cast_.e1.type, e.loc);
            expression(cast_.e1);
            return;
        }
        if (e.op == EXP.address)
        {
            address(e.isUnaExp().e1);
            return;
        }
        if (e.op == EXP.index || e.op == EXP.star)
        {
            address(e);
            loadMemory(e.type, e.loc);
            return;
        }
        if (e.op == EXP.negate || e.op == EXP.uadd || e.op == EXP.not)
        {
            auto operand = e.isUnaExp().e1;
            if (vectorFloat4(operand.type))
            {
                if (e.op != EXP.uadd)
                    reject(e.loc, "ARM32 float4 unary operation is not implemented");
                expression(operand);
                return;
            }
            if (pairType(operand.type))
            {
                if (e.op == EXP.uadd)
                {
                    expression(operand);
                    return;
                }
                if (e.op == EXP.not)
                {
                    condition(operand);
                    code.booleanResult(0);
                    return;
                }
                expression(operand);
                if (operand.type.toBasetype().ty == TY.Tfloat64)
                {
                    code.instruction(0xEC410B10); // VMOV d0,r0,r1
                    code.instruction(0xEEB10B40); // VNEG.F64 d0,d0
                    code.instruction(0xEC510B10); // VMOV r0,r1,d0
                }
                else
                {
                    code.instruction(0xE2700000); // RSBS r0,r0,#0
                    code.instruction(0xE2E11000); // RSC r1,r1,#0
                }
                return;
            }
            if (e.op == EXP.not)
            {
                condition(operand);
                code.booleanResult(0); // EQ
                return;
            }
            expression(operand);
            if (e.op == EXP.uadd)
                return;
            if (floating(operand.type))
            {
                code.instruction(0xEE000A10); // VMOV s0,r0
                code.instruction(0xEEB10A40); // VNEG.F32 s0,s0
                code.instruction(0xEE100A10); // VMOV r0,s0
            }
            else
                code.instruction(0xE2600000); // RSB r0,r0,#0
            return;
        }
        if (auto choice = e.isCondExp())
        {
            condition(choice.econd);
            auto otherwise = code.conditional(0); // EQ => false
            expression(choice.e1);
            auto done = code.branch();
            code.resolve(otherwise, code.bytes.length);
            expression(choice.e2);
            code.resolve(done, code.bytes.length);
            return;
        }
        if (e.op == EXP.halt)
        {
            code.instruction(0xE7F000F0); // UDF #0
            return;
        }

        if (auto call = e.isCallExp())
        {
            directCall(call);
            return;
        }

        auto binary = e.isBinExp();
        if (!binary)
            reject(e.loc, "unsupported expression (allocation and other runtime operations are not implemented)");

        if (e.op == EXP.comma)
        {
            expression(binary.e1);
            expression(binary.e2);
            return;
        }
        if (e.op == EXP.assign || e.op == EXP.construct || e.op == EXP.blit)
        {
            expression(binary.e2);
            assign(binary.e1);
            return;
        }
        if (e.op == EXP.andAnd || e.op == EXP.orOr)
        {
            condition(binary.e1);
            auto shortCircuit = code.conditional(e.op == EXP.andAnd ? 0 : 1);
            condition(binary.e2);
            code.booleanResult(1);
            auto done = code.branch();
            code.resolve(shortCircuit, code.bytes.length);
            code.constant(e.op == EXP.andAnd ? 0 : 1);
            code.resolve(done, code.bytes.length);
            return;
        }

        if (vectorFloat4(binary.e1.type) || vectorFloat4(binary.e2.type))
        {
            if (!vectorFloat4(binary.e1.type) || !vectorFloat4(binary.e2.type) ||
                !vectorFloat4(e.type))
                reject(e.loc, "ARM32 float4 arithmetic requires matching vector operands and result");

            expression(binary.e1);
            const savedVector = temporary(binary.e1.type);
            storeValue(binary.e1.type, savedVector);
            expression(binary.e2);
            code.stackAddress(savedVector * 4);
            code.neonLoadF32x4(1, 12);

            switch (e.op)
            {
            case EXP.add:
                code.neonAddF32x4(0, 1, 0);
                return;
            case EXP.min:
                code.neonSubF32x4(0, 1, 0);
                return;
            case EXP.mul:
                code.neonMulF32x4(0, 1, 0);
                return;
            default:
                reject(e.loc, "ARM32 float4 lowering supports add, subtract and multiply only");
            }
        }

        const isShift = e.op == EXP.leftShift || e.op == EXP.rightShift ||
                        e.op == EXP.unsignedRightShift;
        if (isShift && scalarWords(binary.e1.type) == 2)
        {
            pairShift(e, binary);
            return;
        }

        if (scalarWords(binary.e1.type) == 2 || scalarWords(binary.e2.type) == 2)
        {
            pairBinary(e, binary);
            return;
        }

        expression(binary.e1);
        const saved = temporary();
        code.store(saved);
        expression(binary.e2);
        code.instruction(0xE1A01000); // MOV r1,r0
        code.load(saved);             // left r0, right r1

        const fp = floating(binary.e1.type);
        const unsigned_ = binary.e1.type.toBasetype().ty == TY.Tuns32 ||
                          binary.e1.type.toBasetype().ty == TY.Tpointer;
        if (fp)
        {
            code.instruction(0xEE000A10); // VMOV s0,r0
            code.instruction(0xEE001A90); // VMOV s1,r1
        }

        switch (e.op)
        {
            case EXP.add:
                if (fp) code.instruction(0xEE300A20); // VADD.F32 s0,s0,s1
                else    code.instruction(0xE0800001); // ADD r0,r0,r1
                break;
            case EXP.min:
                if (fp) code.instruction(0xEE300A60); // VSUB.F32 s0,s0,s1
                else    code.instruction(0xE0400001); // SUB r0,r0,r1
                break;
            case EXP.mul:
                if (fp) code.instruction(0xEE200A20); // VMUL.F32 s0,s0,s1
                else    code.instruction(0xE0000190); // MUL r0,r0,r1
                break;
            case EXP.div:
                if (fp)
                    code.instruction(0xEE800A20);     // VDIV.F32 s0,s0,s1
                else
                {
                    const helper = unsigned_ ? "__aeabi_uidiv" : "__aeabi_idiv";
                    const at = code.call();
                    relocations ~= Arm32Relocation(cast(uint)at, helper, ARM32_R_CALL);
                }
                break;
            case EXP.mod:
                if (fp)
                    reject(e.loc, "binary32 remainder is not implemented yet");
                else
                {
                    const helper = unsigned_ ? "__aeabi_uidivmod" : "__aeabi_idivmod";
                    const at = code.call();
                    relocations ~= Arm32Relocation(cast(uint)at, helper, ARM32_R_CALL);
                    code.instruction(0xE1A00001);     // MOV r0,r1: EABI divmod remainder
                }
                break;
            case EXP.and: code.instruction(0xE0000001); break;
            case EXP.or:  code.instruction(0xE1800001); break;
            case EXP.xor: code.instruction(0xE0200001); break;
            case EXP.leftShift:
                code.instruction(0xE1A00110); // LSL r0,r0,r1
                break;
            case EXP.rightShift:
                code.instruction(unsigned_ ? 0xE1A00130 : 0xE1A00150); // LSR/ASR
                break;
            case EXP.unsignedRightShift:
                code.instruction(0xE1A00130); // LSR r0,r0,r1
                break;

            case EXP.equal:
            case EXP.notEqual:
            case EXP.lessThan:
            case EXP.lessOrEqual:
            case EXP.greaterThan:
            case EXP.greaterOrEqual:
            {
                if (fp)
                {
                    code.instruction(0xEEB40A60); // VCMP.F32 s0,s1
                    code.instruction(0xEEF1FA10); // VMRS APSR_nzcv,FPSCR
                }
                else
                    code.instruction(0xE1500001); // CMP r0,r1

                uint cc;
                switch (e.op)
                {
                    case EXP.equal:          cc = 0; break;  // EQ
                    case EXP.notEqual:       cc = 1; break;  // NE
                    case EXP.lessThan:       cc = fp ? 4 : unsigned_ ? 3 : 11; break;
                    case EXP.lessOrEqual:    cc = fp || unsigned_ ? 9 : 13; break;
                    case EXP.greaterThan:    cc = fp ? 12 : unsigned_ ? 8 : 12; break;
                    case EXP.greaterOrEqual: cc = fp ? 10 : unsigned_ ? 2 : 10; break;
                    default: assert(0);
                }
                code.booleanResult(cc);
                return;
            }
            default:
                reject(e.loc, "unsupported binary operation in initial A32 slice");
        }

        if (fp)
            code.instruction(0xEE100A10); // VMOV r0,s0
    }

    void statement(Statement s)
    {
        if (!s)
            return;

        if (auto block = s.isCompoundStatement())
        {
            if (block.statements)
                foreach (child; *block.statements)
                    statement(child);
            return;
        }
        if (auto block = s.isCompoundDeclarationStatement())
        {
            if (block.statements)
                foreach (child; *block.statements)
                    statement(child);
            return;
        }
        if (auto scope_ = s.isScopeStatement())
        {
            statement(scope_.statement);
            return;
        }
        if (auto e = s.isExpStatement())
        {
            expression(e.exp);
            return;
        }
        if (auto ret = s.isReturnStatement())
        {
            expression(ret.exp);
            returns ~= code.bytes.length;
            code.instruction(0xE1A00000); // patched ADD sp,sp,#...
            code.instruction(0xE1A00000);
            code.instruction(0xE8BD8010); // POP {r4,pc}
            return;
        }
        if (auto branch = s.isIfStatement())
        {
            condition(branch.condition);
            auto otherwise = code.conditional(0); // EQ => false
            statement(branch.ifbody);
            auto done = code.branch();
            code.resolve(otherwise, code.bytes.length);
            statement(branch.elsebody);
            code.resolve(done, code.bytes.length);
            return;
        }
        if (auto loop = s.isForStatement())
        {
            emitLoop(loop._init, loop.condition, loop.increment, loop._body);
            return;
        }
        if (auto loop = s.isWhileStatement())
        {
            emitLoop(null, loop.condition, null, loop._body);
            return;
        }
        if (auto break_ = s.isBreakStatement())
        {
            if (!loops.length || break_.ident)
                reject(s.loc, "labelled or non-loop break is unsupported");
            loops[$ - 1].breaks ~= code.branch();
            return;
        }
        if (auto continue_ = s.isContinueStatement())
        {
            if (!loops.length || continue_.ident)
                reject(s.loc, "labelled or non-loop continue is unsupported");
            loops[$ - 1].continues ~= code.branch();
            return;
        }
        if (s.isImportStatement())
            return;

        reject(s.loc, "unsupported statement in initial A32 slice");
    }

    void emitLoop(Statement init, Expression test, Expression increment, Statement body)
    {
        statement(init);
        const start = code.bytes.length;
        loops ~= LoopEdges.init;
        if (test)
        {
            condition(test);
            loops[$ - 1].breaks ~= code.conditional(0); // EQ => false
        }
        statement(body);
        foreach (edge; loops[$ - 1].continues)
            code.resolve(edge, code.bytes.length);
        expression(increment);
        const back = code.branch();
        code.resolve(back, start);
        foreach (edge; loops[$ - 1].breaks)
            code.resolve(edge, code.bytes.length);
        loops.length--;
    }

    Arm32Function emit(FuncDeclaration function_)
    {
        location = function_.loc;
        auto signature = scalarFunction(function_, location);
        auto result = signature.next;

        const parameterCount = function_.parameters ? function_.parameters.length : 0;
        if (parameterCount != signature.parameterList.length)
            reject(location, "A32 scalar definition parameter count does not match its formal parameters");

        string name = functionName(function_, location);

        code.instruction(0xE92D4010); // PUSH {r4,lr}; 8 bytes keeps public SP alignment
        const prologue = code.bytes.length;
        code.instruction(0xE1A00000); // patched SUB sp,sp,#...
        code.instruction(0xE1A00000);

        if (function_.parameters)
        {
            uint ncrn;
            uint stackWords;
            foreach (parameter; *function_.parameters)
            {
                requireScalar(parameter.type, parameter.loc);
                if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                    reject(parameter.loc, "ref/out/lazy parameters are not implemented");

                const words = scalarWords(parameter.type);
                if (words == 2 && (ncrn & 1))
                    ++ncrn;

                ArgumentLocation loc;
                loc.words = words;
                if (ncrn < 4 && words <= 4 - ncrn)
                {
                    loc.reg = cast(int)ncrn;
                    ncrn += words;
                }
                else
                {
                    ncrn = 4;
                    if (words == 2 && (stackWords & 1))
                        ++stackWords;
                    loc.stackWord = stackWords;
                    stackWords += words;
                }

                const parameterHome = temporary(parameter.type);
                bindHome(parameter, parameterHome);
                if (loc.reg >= 0)
                {
                    storeValue(parameter.type, parameterHome, cast(uint)loc.reg);
                }
                else if (words == 1)
                {
                    const at = code.loadStackOffset(0, 0);
                    stackParameterLoads ~= StackParameterLoad(at, loc.stackWord * 4, 0);
                    code.store(parameterHome, 0);
                }
                else
                {
                    const low = code.loadStackOffset(0, 0);
                    const high = code.loadStackOffset(0, 1);
                    stackParameterLoads ~= StackParameterLoad(low, loc.stackWord * 4, 0);
                    stackParameterLoads ~= StackParameterLoad(high, loc.stackWord * 4 + 4, 1);
                    code.storePair(parameterHome, 0);
                }
            }
        }

        statement(function_.fbody);
        if (result.toBasetype().ty == TY.Tvoid)
        {
            returns ~= code.bytes.length;
            code.instruction(0xE1A00000);
            code.instruction(0xE1A00000);
            code.instruction(0xE8BD8010); // POP {r4,pc}
        }
        else
            code.instruction(0xE7F000F0); // unreachable fallthrough traps

        if (globalLiterals.length)
        {
            dataOffsets ~= cast(uint)code.bytes.length;
            foreach (literal; globalLiterals)
            {
                const literalAt = code.bytes.length;
                code.patchLoadLiteral(literal.loadAt, literalAt);
                const pcBase = literal.loadAt + 12; // second LDR uses architectural PC = instruction + 8
                if (literalAt < pcBase)
                    reject(location, "internal A32 GOT literal placement underflow");
                code.instruction(cast(uint)(literalAt - pcBase));
                relocations ~= Arm32Relocation(cast(uint)literalAt, literal.symbol, ARM32_R_GOT_PREL);
            }
        }

        const frame = (slots * 4 + 7) & ~7U;
        code.patchFrame(prologue, frame, true);
        foreach (at; returns)
            code.patchFrame(at, frame, false);
        foreach (load; stackParameterLoads)
            code.patchLoadStackOffset(load.at, frame + 8 + load.incomingOffset, load.reg);

        return Arm32Function(name, code.bytes, relocations, dataOffsets, code.usesNeon);
    }
}

private Arm32Global lowerGlobal(VarDeclaration variable)
{
    const size = scalarBytes(variable.type);
    if (!size)
        reject(variable.loc, "A32 global data currently supports scalar one- and two-word types only");
    if (!variable.isDataseg() || variable.isThreadlocal())
        reject(variable.loc, "A32 global data currently requires non-TLS __gshared/shared storage");
    if (variable.resolvedLinkage() != LINK.c)
        reject(variable.loc, "A32 global data currently requires extern(C) linkage");
    if (variable.isConst() || variable.isImmutable())
        reject(variable.loc, "read-only A32 data sections are not implemented yet");

    const alignment = variable.alignment.isDefault() || variable.alignment.isUnknown() ?
                      size : variable.alignment.get();
    const name = declarationName(variable, variable.loc);
    const defined = !(variable.storage_class & STC.extern_);
    if (!defined)
    {
        if (variable._init)
            reject(variable.loc, "extern A32 global declaration cannot have an initializer");
        return scalarGlobal(name, 0, size, alignment, false);
    }

    if (!variable._init)
        return scalarGlobal(name, 0, size, alignment, true);

    auto initializer = variable._init.isExpInitializer();
    if (!initializer)
        reject(variable.loc, "A32 global initializer must be a scalar constant expression");

    auto value = initializer.exp;
    if (auto integer = value.isIntegerExp())
        return scalarGlobal(name, cast(ulong)integer.value, size, alignment, true);
    if (auto realConstant = value.isRealExp())
    {
        if (floating(variable.type))
        {
            union Payload32
            {
                float value;
                uint bits;
            }
            Payload32 payload;
            payload.value = cast(float)realConstant.value;
            return scalarGlobal(name, payload.bits, 4, alignment, true);
        }
        if (variable.type.toBasetype().ty == TY.Tfloat64)
        {
            union Payload64
            {
                double value;
                ulong bits;
            }
            Payload64 payload;
            payload.value = cast(double)realConstant.value;
            return scalarGlobal(name, payload.bits, 8, alignment, true);
        }
        reject(variable.loc, "floating global constant is outside the float/double A32 subset");
    }
    if (value.op == EXP.null_)
        return scalarGlobal(name, 0, size, alignment, true);

    reject(variable.loc, "A32 global initializer is outside the scalar constant subset");
    assert(0);
}

void generateArm32Objects(Module[] modules)
{
    ubyte[][] objects;
    string[] paths;

    try
    {
        foreach (module_; modules)
        {
            if (module_.filetype == FileType.dhdr)
                continue;

            Arm32Function[] functions;
            Arm32Global[] globals;
            string[] moduleInfos;
            bool[string] names;

            // A plain ordinary-D module has a standalone ModuleInfo record.
            // Module constructors, imports that require initialization, and
            // similar features need further ModuleInfo fields and stay
            // rejected until the A32 data-relocation representation can
            // describe those exact records.
            if (!global.params.betterC && module_.needmoduleinfo)
                reject(module_.loc,
                       "ordinary-D ModuleInfo with lifecycle/import data is not implemented by the A32 object writer");
            if (!global.params.betterC && (!global.params.useModuleInfo || !Module.moduleinfo))
                reject(module_.loc, "ordinary-D A32 emission requires the druntime ModuleInfo interface");

            void members(Dsymbols* symbols)
            {
                if (!symbols)
                    return;
                foreach (symbol; *symbols)
                {
                    if (auto attr = symbol.isAttribDeclaration())
                    {
                        members(include(attr, null));
                        continue;
                    }
                    if (auto function_ = symbol.isFuncDeclaration())
                    {
                        if (function_.isUnitTestDeclaration() && !global.params.useUnitTests)
                            continue;
                        if (!function_.fbody)
                            continue;
                        LeafEmitter emitter;
                        auto functionCode = emitter.emit(function_);
                        if (functionCode.name in names)
                            reject(function_.loc, "duplicate A32 external symbol");
                        names[functionCode.name] = true;
                        functions ~= functionCode;
                        continue;
                    }
                    if (symbol.isImport() || symbol.isAliasDeclaration() ||
                        symbol.isEnumDeclaration() || symbol.isStaticAssert())
                        continue;
                    if (auto variable = symbol.isVarDeclaration())
                    {
                        if (variable.storage_class & STC.manifest)
                            continue;
                        auto global_ = lowerGlobal(variable);
                        if (global_.name in names)
                            reject(variable.loc, "duplicate A32 external symbol");
                        names[global_.name] = true;
                        globals ~= global_;
                        continue;
                    }
                    reject(symbol.loc, "declaration requires data/runtime emission not implemented by the initial A32 slice");
                }
            }

            members(module_.members);
            if (!global.params.betterC)
            {
                auto info = standaloneModuleInfo(module_);
                if (info.name in names)
                    reject(module_.loc, "ordinary-D ModuleInfo collides with an emitted A32 symbol");
                names[info.name] = true;
                globals ~= info;
                moduleInfos ~= info.name;
            }
            objects ~= arm32Object(functions, globals, moduleInfos);
            paths ~= module_.objfile.toString().idup;
        }

        foreach (i, path; paths)
        {
            auto parent = dirName(path);
            if (parent.length && !exists(parent))
                mkdirRecurse(parent);
            const temporaryPath = path ~ ".arm32-tmp";
            write(temporaryPath, objects[i]);
            rename(temporaryPath, path);
        }
    }
    catch (UnsupportedArm32 failure)
    {
        foreach (module_; modules)
            if (module_.filetype != FileType.dhdr)
                module_.deleteObjFile();
        error(failure.location, "A32 backend: %.*s", cast(int)failure.msg.length, failure.msg.ptr);
    }
    catch (Exception failure)
    {
        foreach (module_; modules)
            if (module_.filetype != FileType.dhdr)
                module_.deleteObjFile();
        error(Loc.initial, "A32 emission failed: %.*s", cast(int)failure.msg.length, failure.msg.ptr);
    }
}
