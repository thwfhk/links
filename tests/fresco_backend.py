#!/usr/bin/env python3
"""Execute checked handler programs in the interpreter and bundled JS runtime."""
import pathlib
import shlex
import shutil
import subprocess
import tempfile

NODE = shutil.which("node")
assert NODE, "Node is required for JavaScript execution checks"
BASE = ["./links", "--config=tests/fresco_modal.config",
        "--set=recheck_frontend_transformations=true"]
LEGACY = ["./links", "--config=tests/legacy_compatibility.config", "--enable-handlers",
          "--set=prelude=tests/empty_prelude.links"]

# Each case supplies declarations, an Int expression, its result and print calls.
CASES = [
    ("inferred-reader", "effect Reader(a::Abs) { Ask:()=>a; }", """
      handle (do Reader.Ask) {case x->x case <Ask=>k> -> k(42)}
    """, 42, []),
    ("distinct-identities", "effect A { Read:()=>Int; } effect B { Read:()=>Int; }", """
      handle <A> (handle <B> (do A.Read + do B.Read) {
        case x->x case <B.Read=>k> -> k(2)
      }) {case x->x case <A.Read=>k> -> k(40)}
    """, 42, []),
    ("repeated-typed-identity", "effect Reader(a::Abs) { Ask:()=>a; }", """
      handle <Reader(Int)> ({
        var bit=handle <Reader(Bool)> ((do Ask) && (do Ask)) {
          case x->if(x) 1 else 0
          case <Ask=>k> -> k((do Ask)==20)
        };
        bit + do Ask
      }) {case x->x case <Ask=>k> -> k(20)}
    """, 21, []),
    ("deep-reinstalls-handler", "effect Tick { Next:()=>Int; }", """
      handle <Tick> (handle <Tick> ({var x=do Next; x+do Next}) {
        case x->x case <Next=>k> -> k(do Next+1)
      }) {case x->x case <Next=>k> -> k(21)}
    """, 44, []),
    ("handler-parameters", "effect State { Get:()=>Int; Put:(Int)=>(); }", """
      handle ({do Put(40); var first=do Get; do Put(first+2); do Get})(s<-0) {
        case x->x
        case <Get=>k> -> k(s,s)
        case <Put(n)=>k> -> k((),n)
      }
    """, 42, []),
    ("nested-parameters", "effect State { Get:()=>Int; Put:(Int)=>(); }", """
      handle ({
        var inner=handle ({do Put(40); do Get})(s<-20) {
          case x->x
          case <Get=>k> -> k(s,s)
          case <Put(n)=>k> -> k((),n+do Get)
        };
        inner+do Get
      })(s<-1) {
        case x->x
        case <Get=>k> -> k(s,s)
        case <Put(n)=>k> -> k((),n)
      }
    """, 42, []),
    ("captured-closures", "effect Reader { Ask:()=>Int; }", """
      handle <Reader> ({
        var seed=2;
        var f=fun(x) {var thunk=fun() {do Ask+x+seed}; thunk()};
        f(0)+f(0)
      }) {case x->x case <Ask=>k> -> k(19)}
    """, 42, []),
    ("returned-closure", "effect Reader { Ask:()=>Int; }", """
      var f=handle <Reader> ({var x=do Ask; (fun(y) {x+y}:modal [] ((Int)->Int))}) {
        case f->f case <Ask=>k> -> k(40)
      };
      f(2)
    """, 42, []),
    ("reusable-resumption", "effect Choice { Choose:()=>Bool; }", """
      handle (if(do Choose) 20 else 22) {
        case x->x case <Choose=>k> -> k(true)+k(false)
      }
    """, 42, []),
    ("polymorphic-effect-argument", """
      typename Identity=modal [] (forall a. (a)->a);
      effect Reader(a::Abs) { Ask:()=>a; }
    """, """
      handle <Reader(Identity)> ({var f=do Ask; if(f(true)) f(42) else 0}) {
        case x->x case <Ask=>k> -> k((fun(x) {x}:Identity))
      }
    """, 42, []),
    ("resumption-order", "effect Tick { Next:()=>Int; }", """
      handle ({print("before"); var x=do Next; print("after"); x+2}) {
        case x->x
        case <Next=>k> -> print("clause"); var result=k(40); print("resumed"); result
      }
    """, 42, ["before", "clause", "after", "resumed"]),
]

SHALLOW = ("effect Tick { Next:()=>Int; }", """
  shallowhandle <Tick> ({var x=do Next; x+do Next}) {
    case x->x
    case <Next=>k> -> handle <Tick> (k(1)) {
      case x->x case <Next=>again> -> again(10)
    }
  }
""")


def invoke(command, expected=None, error=None):
    print("$ " + shlex.join(command), flush=True)
    result = subprocess.run(command, capture_output=True, text=True, timeout=40)
    print(result.stdout, end="", flush=True)
    print(result.stderr, end="", flush=True)
    assert (result.returncode == 0) == (error is None), result.returncode
    if error:
        assert error in result.stderr, (error, result.stderr)
    else:
        assert result.stderr == "", result.stderr
    if expected is not None:
        assert result.stdout == expected, (expected, result.stdout)
    return result


def source(declarations, expression):
    return (declarations + "\nvar result={" + expression + "};\n"
            '{print("RESULT:" ^^ intToString(result)); ()}')


def compile_to(directory, label, program, options, error=None, file_input=False, base=BASE):
    output = directory / (label + ".js")
    inputs = ["-e", program]
    if file_input:
        filename = directory / (label + ".links")
        filename.write_text(program)
        inputs = [str(filename)]
    invoke(base + options + ["--compile", "-o", str(output)] + inputs, "", error)
    if error:
        assert not output.exists(), output
        return
    code = output.read_text()
    assert "/* SCHEDULER */" in code, "The bundled runtime must be linked"
    assert "Higher-order continuation module." in code
    return output


def handlers(directory):
    count = 0
    for selector, flag in [("default", []), ("explicit", ["--fresco"])]:
        for optimise in [False, True]:
            options = flag + ["--set=optimise=" + str(optimise).lower()]
            for name, declarations, expression, result, prints in CASES:
                label = name + "-" + selector + "-" + str(optimise).lower()
                print("\nCASE " + label, flush=True)
                program = source(declarations, expression)
                marker = "RESULT:" + str(result)
                invoke(BASE + options + ["-e", program], "".join(prints) + marker + "() : ()\n")
                output = compile_to(directory, label, program, options)
                invoke([NODE, str(output)], "\n".join(prints + [marker]) + "\n")
                count += 1
            declarations, expression = SHALLOW
            program = source(declarations, expression)
            invoke(BASE + options + ["-e", program], "RESULT:11() : ()\n")
            compile_to(directory, "shallow-" + selector + "-" + str(optimise).lower(),
                       program, options, error="shallow handlers")
    print(str(count) + " paired interpreter/JavaScript handler executions passed", flush=True)
    print("4 interpreter shallow executions and 4 JavaScript shallow rejections passed", flush=True)


def ordinary_and_legacy(directory):
    for name, selector in [("ordinary", []), ("legacy", ["--set=fresco=false"])]:
        options = selector + ["--set=enable_handlers=false"]
        output = directory / (name + ".js")
        filename = directory / (name + ".links")
        filename.write_text('print("RESULT:42")')
        invoke(BASE + options + ["--compile", "-o", str(output), str(filename)], "")
        with output.open("a") as stream:
            stream.write('\nif ((function() {return this;})() !== globalThis) '
                         'throw new Error("Standalone script mode changed");\n')
        invoke([NODE, str(output)], "RESULT:42\n")
    program = 'var result=handle (do Read) {case x->x case <Read=>k> -> k(42)}; print(intToString(result))'
    print("Legacy handler runtime uses tests/legacy_compatibility.config", flush=True)
    output = compile_to(directory, "legacy-handler", program, [], file_input=True, base=LEGACY)
    invoke([NODE, str(output)], "42\n")


def custom_runtime(directory):
    runtime = directory / "custom.js"
    runtime.write_text("""const startupKind = _$K.kind;
const _$Proc = {yield: function(f) {return f();}};
function _default_receive() {throw new Error("Unexpected receive");}
function print(s,k) {console.info(startupKind + ":" + s); return _$K.apply(k,{});}
""")
    output = directory / "custom-output.js"
    options = ["--set=enable_handlers=false", "--Xcustom-js-runtime=" + str(runtime)]
    invoke(BASE + options + ["--compile", "-o", str(output), "-e", 'print("RESULT:42")'], "")
    invoke([NODE, str(output)], "Default_Continuation:RESULT:42\n")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="links-fresco-backend-") as temporary:
        directory = pathlib.Path(temporary)
        handlers(directory)
        ordinary_and_legacy(directory)
        custom_runtime(directory)
    print("Bundled and custom runtime execution checks passed", flush=True)
