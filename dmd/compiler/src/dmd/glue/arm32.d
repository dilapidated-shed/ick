/**
 * Typed DMD AST -> ARMv7-A A32 BetterC code.
 *
 * This is the first A32 lowering slice. It uses DMD's parser and semantic
 * passes, follows AAPCS32 base PCS for one-word scalar arguments, and emits
 * A32 instructions only. Unsupported constructs fail closed.
 *
 * License: Boost License 1.0
 */
module dmd.glue.arm32;

import dmd.astenums : TY, STC, LINK, VarArg, FileType;
import dmd.arraytypes : Dsymbols;
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
import dmd.mtype;
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

private struct LeafEmitter
{
    Arm32Code code;
    Arm32Relocation[] relocations;
    uint[VarDeclaration] homes;
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

    uint temporary()
    {
        if (slots >= 126)
            reject(location, "A32 leaf frame exceeds 504 bytes");
        return slots++;
    }

    uint home(VarDeclaration variable)
    {
        auto found = variable in homes;
        if (!found)
            reject(variable.loc, "global, captured, or uninitialised variable is outside the initial A32 slice");
        return *found;
    }

    void requireWord(Type t, Loc loc)
    {
        if (!wordType(t))
            reject(loc, "initial A32 lowering supports float, int, uint, bool and pointers");
    }

    string globalName(VarDeclaration variable)
    {
        requireWord(variable.type, variable.loc);
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
        expression(expression_);
        if (floating(expression_.type))
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
            if (declaration in homes)
                reject(expression_.loc, "taking the address of an A32 stack local is not implemented");
            globalAddress(declaration);
            return;
        }
        if (auto index = expression_.isIndexExp())
        {
            if (index.e1.type.toBasetype().ty != TY.Tpointer ||
                !wordType(index.type) || index.type.toBasetype().ty == TY.Tbool)
                reject(index.loc, "only caller-owned four-byte pointer elements are supported");
            expression(index.e1);
            const saved = temporary();
            code.store(saved);
            expression(index.e2);
            code.instruction(0xE1A01000); // MOV r1,r0
            code.instruction(0xE1A01101); // MOV r1,r1,LSL #2
            code.load(saved);
            code.instruction(0xE0800001); // ADD r0,r0,r1
            return;
        }
        if (expression_.op == EXP.star)
        {
            if (expression_.type.toBasetype().ty == TY.Tbool)
                reject(expression_.loc, "byte-sized memory accesses are not implemented");
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
            if (auto found = declaration in homes)
            {
                code.store(*found);
                return;
            }

            const saved = temporary();
            code.store(saved);
            globalAddress(declaration);
            code.load(saved, 1);
            code.instruction(0xE5801000); // STR r1,[r0]
            code.instruction(0xE1A00001); // MOV r0,r1
            return;
        }
        const saved = temporary();
        code.store(saved);
        address(destination);
        code.load(saved, 1);
        code.instruction(0xE5801000); // STR r1,[r0]
        code.instruction(0xE1A00001); // MOV r0,r1
    }

    void declare(VarDeclaration variable)
    {
        requireWord(variable.type, variable.loc);
        if (variable.storage_class & (STC.static_ | STC.ref_ | STC.out_ | STC.lazy_))
            reject(variable.loc, "static and by-reference locals are outside the initial A32 slice");
        homes[variable] = temporary();
        auto initializer = variable._init ? variable._init.isExpInitializer() : null;
        if (!initializer)
            reject(variable.loc, "local requires an expression initializer");
        expression(initializer.exp);
        code.store(home(variable));
    }

    void directCall(CallExp call)
    {
        auto callee = call.f;
        if (!callee)
            reject(call.loc, "indirect/function-pointer calls are not implemented");
        if (callee.resolvedLinkage() != LINK.c || callee.isNested() || callee.isMember())
            reject(call.loc, "A32 direct calls currently require top-level extern(C) functions");

        auto signature = callee.type.toTypeFunction();
        if (signature.parameterList.varargs != VarArg.none || signature.isRef)
            reject(call.loc, "variadic or ref-return calls are not implemented");
        if (signature.next.toBasetype().ty != TY.Tvoid)
            requireWord(signature.next, call.loc);

        const count = call.arguments ? cast(uint)call.arguments.length : 0U;
        if (count > 64)
            reject(call.loc, "more than 64 one-word call arguments are outside the qualification range");

        if (callee.parameters)
        {
            foreach (parameter; *callee.parameters)
                if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                    reject(call.loc, "ref/out/lazy call parameters are not implemented");
        }

        uint[] argumentHomes;
        argumentHomes.length = count;
        if (call.arguments)
        {
            foreach (i, argument; *call.arguments)
            {
                requireWord(argument.type, argument.loc);
                expression(argument);
                argumentHomes[i] = temporary();
                code.store(argumentHomes[i]);
            }
        }

        const stackWords = count > 4 ? count - 4 : 0U;
        const outgoing = (stackWords * 4 + 7) & ~7U;
        code.adjustStack(outgoing, true);

        foreach (i; 4 .. count)
        {
            code.loadStackOffset(outgoing + argumentHomes[i] * 4, 0);
            code.storeStackOffset((i - 4) * 4, 0);
        }
        foreach (i; 0 .. (count < 4 ? count : 4))
            code.loadStackOffset(outgoing + argumentHomes[i] * 4, i);

        const at = code.call();
        relocations ~= Arm32Relocation(cast(uint)at, declarationName(callee, call.loc), ARM32_R_CALL);
        code.adjustStack(outgoing, false);
    }

    void expression(Expression e)
    {
        if (!e)
            return;
        if (++depth > 128)
            reject(e.loc, "A32 expression nesting exceeds 128");
        scope(exit) --depth;

        if (e.type && e.type.toBasetype().ty != TY.Tvoid && e.op != EXP.declaration)
            requireWord(e.type, e.loc);

        if (auto integer = e.isIntegerExp())
        {
            code.constant(cast(uint)integer.value);
            return;
        }
        if (auto realConstant = e.isRealExp())
        {
            if (!floating(e.type))
                reject(e.loc, "only binary32 floating constants are implemented");
            union Payload
            {
                float value;
                uint bits;
            }
            Payload payload;
            payload.value = cast(float)realConstant.value;
            code.constant(payload.bits);
            return;
        }
        if (e.op == EXP.null_)
        {
            code.constant(0);
            return;
        }
        if (auto variable = e.isVarExp())
        {
            auto declaration = variable.var.isVarDeclaration();
            if (!declaration)
                reject(e.loc, "function values are outside the initial A32 slice");
            if (auto found = declaration in homes)
                code.load(*found);
            else
            {
                globalAddress(declaration);
                code.instruction(0xE5900000); // LDR r0,[r0]
            }
            return;
        }
        if (auto declaration = e.isDeclarationExp())
        {
            auto variable = declaration.declaration.isVarDeclaration();
            if (!variable)
                reject(e.loc, "only scalar local declarations are implemented");
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
            code.instruction(0xE5900000); // LDR r0,[r0]
            return;
        }
        if (e.op == EXP.negate || e.op == EXP.uadd || e.op == EXP.not)
        {
            auto operand = e.isUnaExp().e1;
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
        if (function_.resolvedLinkage() != LINK.c || function_.isNested() || function_.isMember())
            reject(location, "initial A32 lowering accepts top-level extern(C) functions only");

        auto signature = function_.type.toTypeFunction();
        if (signature.parameterList.varargs != VarArg.none || signature.isRef)
            reject(location, "variadic or ref-return functions are not implemented");

        auto result = signature.next;
        if (result.toBasetype().ty != TY.Tvoid)
            requireWord(result, location);

        if (function_.parameters && function_.parameters.length > 64)
            reject(location, "more than 64 one-word parameters are outside the qualification range");

        string name = declarationName(function_, location);

        code.instruction(0xE92D4010); // PUSH {r4,lr}; 8 bytes keeps public SP alignment
        const prologue = code.bytes.length;
        code.instruction(0xE1A00000); // patched SUB sp,sp,#...
        code.instruction(0xE1A00000);

        if (function_.parameters)
        {
            foreach (i, parameter; *function_.parameters)
            {
                requireWord(parameter.type, parameter.loc);
                if (parameter.storage_class & (STC.ref_ | STC.out_ | STC.lazy_))
                    reject(parameter.loc, "ref/out/lazy parameters are not implemented");

                homes[parameter] = temporary();
                if (i < 4)
                {
                    code.store(homes[parameter], cast(uint)i);
                }
                else
                {
                    const at = code.loadStackOffset(0);
                    stackParameterLoads ~= StackParameterLoad(at, cast(uint)(i - 4) * 4);
                    code.store(homes[parameter]);
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
            code.patchLoadStackOffset(load.at, frame + 8 + load.incomingOffset);

        return Arm32Function(name, code.bytes, relocations, dataOffsets);
    }
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
            bool[string] names;

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
                    }
                    reject(symbol.loc, "declaration requires data/runtime emission not implemented by the initial A32 slice");
                }
            }

            members(module_.members);
            objects ~= arm32Object(functions);
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
