#!/usr/bin/env python3
"""Contextual compile checks. Only isolated arithmetic wrappers execute in Node."""
import pathlib
import re
import shlex
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path.cwd()
EMPTY = "tests/empty_prelude.links"
CUSTOM = "tests/fixtures/fresco_batch/customPrelude.links"
BASE = ["./links", "--compile", "--set=optimise=false",
        "--set=typecheck_ir=true", "--set=fail_on_ir_type_error=true",
        "--set=recheck_frontend_transformations=true"]
NODE = shutil.which("node")
assert NODE, "Node is required for JavaScript syntax checks"


def invoke(command, success=True, error=None):
    print("$ " + shlex.join(command), flush=True)
    result = subprocess.run(command, capture_output=True, text=True, timeout=35)
    print(result.stdout, end="", flush=True)
    print(result.stderr, end="", flush=True)
    assert (result.returncode == 0) == success, result.returncode
    assert result.stdout == "", "Compile mode evaluated source: " + result.stdout
    if error:
        assert error in result.stderr, (error, result.stderr)
    elif success:
        assert result.stderr == "", result.stderr
    return result


def compile_to(directory, label, sources, options=(), prelude=EMPTY, success=True, error=None, earlier_output=False):
    output = directory / (label + ".js")
    command = BASE + (["--set=prelude=" + prelude] if prelude is not None else [])
    command += list(options) + ["-o", str(output)] + list(sources)
    invoke(command, success, error)
    if not success:
        assert output.exists() == earlier_output, output
        return output.read_text() if earlier_output else ""
    assert output.is_file(), output
    invoke([NODE, "--check", str(output)])
    return output.read_text()


def file(directory, name, source):
    path = directory / name
    path.write_text(source)
    return str(path)


def ordinary(directory):
    code = compile_to(directory, "default", ["-e", '(map(fun(x) { x+1 },[40,41]),Just(42):Maybe(Int))'], prelude=None)
    assert "function" in code
    compile_to(directory, "empty", ["-e", "42"])
    compile_to(directory, "empty-missing", ["-e", "map(fun(x){x},[42])"], success=False, error="Unbound variable map")


def custom_and_weak(directory):
    code = compile_to(directory, "custom", ["-e", '{print("BODY-MARKER");seed+2}'], prelude=CUSTOM)
    for marker in ["'prelude:'", "'tail:'", "'BODY-MARKER'"]:
        assert code.count(marker) == 1, marker
    assert code.index("'prelude:'") < code.index("'tail:'") < code.index("'BODY-MARKER'")
    weak = file(directory, "weakPrelude.links", "var identity=fun(x) { x }; ()")
    compile_to(directory, "weak", ["-e", "identity(42)"], prelude=weak)


def expression_order(directory):
    source = file(directory, "use.links", '{print("FILE-MARKER");saved+2}')
    expression = 'var saved={print("EXPRESSION-MARKER");40}; saved'
    code = compile_to(directory, "shared-expression", ["-e", expression, source], ["--set=isolation=false"])
    assert code.index("'EXPRESSION-MARKER'") < code.index("'FILE-MARKER'")
    compile_to(directory, "isolated-expression", ["-e", "var saved=40; saved", source],
               success=False, error="Unbound variable saved", earlier_output=True)


def multiple_inputs(directory):
    first = file(directory, "first.links", '{print("FIRST-INPUT");1}')
    last = file(directory, "last.links", '{print("LAST-INPUT");42}')
    isolated = compile_to(directory, "isolated-files", [first,last])
    assert "LAST-INPUT" in isolated and "FIRST-INPUT" not in isolated
    shared = compile_to(directory, "shared-files", [first,last], ["--set=isolation=false"])
    assert shared.index("'FIRST-INPUT'") < shared.index("'LAST-INPUT'")


def modules(directory):
    first = file(directory, "import-first.links", "open import CompileShared; shared")
    last = file(directory, "import-last.links", "open import CompileShared; shared+2")
    code = compile_to(directory, "modules", [first,last],
                      ["--set=isolation=false", "--path=tests/fixtures/fresco_compile"])
    assert code.count("'MODULE-ONCE'") == 1


def handlers(directory):
    deep = "effect E {Read:()=>Int;} handle <E> (do Read) {case x->x case <Read => k> -> k(42)}"
    compile_to(directory, "deep", ["-e",deep], ["--enable-handlers"])
    shallow = "effect E {Read:()=>Int;} shallowhandle (do Read) {case x->x case <Read => k> -> 42}"
    compile_to(directory, "shallow", ["-e",shallow], ["--enable-handlers"],
               success=False, error="shallow handlers")


def runtime_and_arithmetic(directory):
    # This small synchronous runtime tests only the repaired primitive wrappers.
    runtime = file(directory, "arithmetic-runtime.js", """// CUSTOM-RUNTIME-MARKER
const _$Proc = {yield: function(f) {return f();}};
function _default_receive() {throw new Error("Unexpected receive in arithmetic control");}
function print(s,k) {process.stdout.write(s);return _$K.apply(k,{});}
function intToString(x,k) {return _$K.apply(k,String(x));}
function floatToString(x,k) {return _$K.apply(k,String(x));}
""")
    source = ('var integer=negate; var floating=negatef; var add=fun(x,y){x+y}; '
              '{print(intToString(integer(42)));print(",");'
              'print(floatToString(floating(2.5)));print(",");print(intToString(add(40,2)));42}')
    output = directory / "arithmetic.js"
    command = BASE + ["--set=prelude=" + EMPTY, "--mode=compile", "--output", str(output),
                      "--Xcustom-js-runtime=" + runtime, "-e", source]
    invoke(command)
    code = output.read_text()
    assert "CUSTOM-RUNTIME-MARKER" in code
    assert len(re.findall(r"function\(x, __kappa\)", code)) == 2
    assert re.search(r"function\(x, y, __kappa\)", code)
    invoke([NODE, "--check", str(output)])
    result = subprocess.run([NODE,str(output)], capture_output=True, text=True, timeout=8)
    print("isolated arithmetic result: " + result.stdout, flush=True)
    assert result.returncode == 0 and result.stdout == "-42,-2.5,42" and result.stderr == "", result
    no_runtime = compile_to(directory, "no-runtime", ["-e","42"], ["--Ljs-runtime"])
    assert "First-order continuation module" not in no_runtime and "CUSTOM-RUNTIME-MARKER" not in no_runtime


def check_only_and_empty(directory):
    output = directory / "check-only.js"
    invoke(BASE + ["--set=prelude=" + CUSTOM, "--set=typecheck_only=true", "-o",str(output),
                   "-e", 'sig absurd:(Int)->Int fun absurd(x){switch(x){}} absurd(seed)'])
    assert not output.exists()
    invoke(BASE + ["--set=prelude=" + EMPTY], False, "requires a source file or -e")


def errors(directory):
    compile_to(directory, "source-error", ["-e",'{print("MUST-NOT-EVALUATE");true+1}'],
               success=False, error="Type error")
    missing = directory / "missing-directory" / "out.js"
    invoke(BASE + ["--set=prelude=" + EMPTY,"-o",str(missing),"-e","42"], False, "Cannot open")


def legacy(directory):
    source = file(directory, "legacy.links", "42")
    compile_to(directory, "legacy", [source], ["--set=fresco=false"])
    compile_to(directory, "affirmative-config", ["-e", "sig id:modal [] ((Int)->Int) fun id(x){x} id(42)"],
               ["--config=tests/legacy_compatibility.config", "--fresco"])


if __name__ == "__main__":
    cases = [ordinary,custom_and_weak,expression_order,multiple_inputs,modules,
             handlers,runtime_and_arithmetic,check_only_and_empty,errors,legacy]
    with tempfile.TemporaryDirectory(prefix="links-fresco-compile-") as temporary:
        directory = pathlib.Path(temporary)
        for case in cases:
            print("\nCASE " + case.__name__, flush=True)
            case(directory)
            print("PASS " + case.__name__, flush=True)
    print(str(len(cases)) + " contextual compile cases passed", flush=True)
