(* IMP: Need to fix findescape for classes! *)
(* A FindEscape function can look for escaping variables and record this information in the escape fields of the abstract syntax. The simplest way is to traverse the entire abstract syntax tree, looking for escaping uses of every variable. This phase must occur before semantic analysis begins, since Semant needs to know whether a variable escapes immediately upon seeing that variable for the first time. *)

(* Idea of finding escapes is straight forward: Just see if this thing was defined in outer scope *)

structure FindEscape: sig val findEscape: Absyn.exp -> unit end =
struct

structure S = Symbol
structure A = Absyn

type depth = int
type escEnv = (depth * bool ref) S.table

fun partitionClassFields ([], a, b) = (a, b)
  | partitionClassFields (cf :: cfs, a, b) = 
    case cf of 
      A.VarDec (_) => partitionClassFields (cfs, a @ [cf], b)
    | _ => partitionClassFields (cfs, a, b @ [cf])

fun traverseVar(env : escEnv, d : depth, s : A.var): unit =
case s of
    A.SimpleVar(sym, pos) =>
        (case S.look(env, sym) of
            SOME(d', esc) => if d > d' then esc := true else ())
    | A.FieldVar(var, sym, pos) => traverseVar(env, d, var)
    | A.SubscriptVar(var, exp, pos) => traverseVar(env, d, var)

and traverseExp(env : escEnv, d : depth, s : A.exp): unit =
case s of
      A.NilExp => ()
    | A.IntExp(_) => ()
    | A.RealExp(_) => ()
    | A.StringExp(_, _) => ()
    | A.ClassObject(_) => ()
    (* Since when calling, user won't give class self as compiler is doing it, this is fine! *)
    | A.ClassCallExp({lvalue, args, ...}) => (traverseVar(env, d, lvalue); app (fn arg => traverseExp(env, d, arg)) args)
    | A.CallExp({args, ...}) => app (fn arg => traverseExp(env, d, arg)) args
    | A.ArrayExp({size, init, ...}) => (traverseExp(env, d, size); traverseExp(env, d, init))
    | A.RecordExp({fields, ...}) => app (fn (_, exp, _) => traverseExp(env, d, exp)) fields
    | A.OpExp({left, right, ...}) => (traverseExp(env, d, left); traverseExp(env, d, right))
    | A.SeqExp(exps) => app (fn (exp, _) => traverseExp(env, d, exp)) exps
    | A.IfExp({test, then', else', ...}) =>
        (traverseExp(env, d, test); traverseExp(env, d, then');
        (case else' of
              SOME(else'') => traverseExp(env, d, else'')
            | NONE => ()))
    | A.WhileExp({test, body, ...}) => (traverseExp(env, d, test); traverseExp(env, d, body))
    | A.LetExp({decs, body, ...}) =>
        let 
            val env' = traverseDecs(env, d, decs) 
        in
            traverseExp(env', d, body)
        end
    | A.ForExp({var, escape, lo, hi, body, pos}) =>
        let 
            val env' = (escape := false; S.enter(env, var, (d, escape)) )
        in
        (
            traverseExp(env, d, lo);
            traverseExp(env, d, hi);
            traverseExp(env', d, body)
        )
        end
    | A.BreakExp(_) => ()
    | A.AssignExp({var, exp, ...}) => (traverseVar(env, d, var); traverseExp(env, d, exp))
    | A.VarExp(var) => traverseVar(env, d, var)

and traverseDecs(env, d, s : A.dec list): escEnv =
let 
    fun traverseDec (dec, env) =
    case dec of
        A.FunctionDec(fundecs) =>
        foldl 
            (fn ({params, body, ...}, env) =>
            let 
                val env' = (foldl 
                    (fn ({name, escape, ...}, env) =>
                        (escape := false; S.enter(env, name, (d + 1, escape)))
                    ) env params)
            in 
                (traverseExp(env', d + 1, body); env) 
            end
            ) env fundecs
        | A.VarDec({name, escape, init, ...}) => (escape := false; traverseExp(env, d, init); S.enter(env, name, (d, escape)))
        | A.TypeDec(_) => env
        | A.ClassDec({classFields, ...}) => (* here for var declaration, it is not getting added into the environment *)
        ( 
            let 
                (* Here VarDecs have no role as "VarDecs" thus their escape is irrelevant, just need to traverseExp of init *)
                val (varDecs, funDecs) = partitionClassFields(classFields, [], [])
            in 
            (
                app (fn (A.VarDec({init, ...})) => traverseExp(env, d, init)) varDecs;
                traverseDecs(env, d, funDecs)
            )
            end
        ) 
in 
    foldl traverseDec env s 
end

fun findEscape(prog : A.exp): unit =
    let 
        val st = S.empty
    in
        traverseExp(st, 0, prog)
    end
end