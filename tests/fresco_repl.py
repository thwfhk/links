#!/usr/bin/env python3
"""Bounded stdin checks for the contextual REPL. Run from the repository root."""
import os
import select
import signal
import subprocess
import time

PROMPT = b"links> "


class Repl:
    def __init__(self):
        self.process = subprocess.Popen(
            ["_build/default/bin/links.exe", "--fresco", "--enable-handlers",
             "--set=prelude=tests/empty_prelude.links", "--set=native_readline=false",
             "--set=optimise=false", "--set=typecheck_ir=true",
             "--set=fail_on_ir_type_error=true", "--set=recheck_frontend_transformations=true",
             "--path=tests/fixtures/fresco_repl"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        self.transcript = ""
        self.welcome = self.read_prompt()

    def read_prompt(self):
        output = b""
        deadline = time.monotonic() + 8
        while not output.endswith(PROMPT):
            if time.monotonic() >= deadline:
                raise AssertionError("REPL prompt timeout: " + output.decode(errors="replace"))
            if select.select([self.process.stdout], [], [], 0.1)[0]:
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise AssertionError("REPL exited before prompt: " + output.decode(errors="replace"))
                output += chunk
        text = output.decode(errors="replace")
        self.transcript += text
        return text

    def command(self, source):
        print(">>> " + source, flush=True)
        self.process.stdin.write((source + "\n").encode())
        self.process.stdin.flush()
        text = self.read_prompt()
        print(text, end="", flush=True)
        return text

    def close(self, eof=False):
        if self.process.poll() is None:
            if eof:
                self.process.stdin.close()
            else:
                self.process.stdin.write(b"@quit;\n")
                self.process.stdin.flush()
            self.process.wait(timeout=8)
        assert self.process.returncode == 0, self.process.returncode

    def cleanup(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait(timeout=3)
        if self.process.stdin and not self.process.stdin.closed:
            self.process.stdin.close()
        self.process.stdout.close()


def require(text, *parts):
    for part in parts:
        assert part in text, (part, text)


def definitions(repl):
    require(repl.welcome, "Welcome to Links version")
    require(repl.command("var x=40;"), "x = 40 : Int")
    require(repl.command("var x=42;"), "x = 42 : Int")
    require(repl.command("var x=true+1;"), "Type error")
    require(repl.command("var broken=;"), "Parse error")
    require(repl.command("x;"), "42 : Int")


def polymorphism(repl):
    require(repl.command("typename Identity=modal [] (forall a.(a)->a);"),
            "Identity = modal [] (forall")
    require(repl.command("sig identity:Identity fun identity(x) { x };"), "identity = fun : Identity")
    require(repl.command("(identity(42),identity(true));"), "(42, true) : (Int, Bool)")
    require(repl.command("sig increment:modal [] ((Int)->Int) fun increment(x) { x+1 };"),
            "increment = fun")
    require(repl.command("increment(41);"), "42 : Int")


def alias_changes(repl):
    require(repl.command("typename Number=Int;"), "Number = Int")
    unchanged = repl.command("var later=42;")
    assert "Number =" not in unchanged, unchanged
    require(repl.command("typename Number=Bool;"), "Number = Bool")
    require(repl.command("@tyconenv;"), "Number = Bool")


def environments(repl):
    repl.command("var identity=fun(x) { x };")
    repl.command("identity(42);")
    for directive in ["@env;", "@typeenv;"]:
        text = repl.command(directive)
        require(text, "identity", "Int")
        assert "modal [effect_0$Wild]" not in text, text
    builtins = repl.command("@builtins;")
    require(builtins, "spawnWait", "modal", "Receive", "Process")
    assert "~>" not in builtins, builtins


def loading(repl):
    require(repl.command('@load "tests/fixtures/fresco_repl/good.links";'),
            "Loaded = Int", "loaded = 40 : Int", "42 : Int")
    require(repl.command('@load "tests/fixtures/fresco_repl/bad.links";'), "Type error")
    require(repl.command("loaded+2;"), "42 : Int")
    require(repl.command('@load "tests/fixtures/fresco_repl/missing.links";'), "missing.links")
    require(repl.command("loaded+2;"), "42 : Int")


def imports(repl):
    first = repl.command("open import ReplShared;")
    require(first, "module-once:", "SharedAlias = Int", "moduleValue = 40")
    repeated = repl.command("open import ReplShared;")
    assert "module-once:" not in repeated and "SharedAlias =" not in repeated, repeated
    require(repl.command("moduleValue+2;"), "42 : Int")


def settings(repl):
    require(repl.command("@directives;"), "@load", "@builtins", "@help")
    require(repl.command("@help printing_types;"), "printing_types", "Print types")
    require(repl.command("@settings;"), "printing_types", "print_pretty")
    require(repl.command("@withtype Int;"), "not yet supported")
    require(repl.command('@dload "missing-repl-extension.cmxs";'), "dynamic linking error")
    require(repl.command("@unknown;"), "unknown directive")
    require(repl.command("40+2;"), "42 : Int")


def printing(repl):
    repl.command("@set printing_types false;")
    plain = repl.command("(answer=42);")
    require(plain, "answer", "42")
    assert ":" not in plain, plain
    repl.command("@set print_colours true;")
    coloured = repl.command("A;")
    require(coloured, "\x1b[32m", "A")
    repl.command("@set print_pretty false;")
    plain = repl.command("A;")
    assert "\x1b[" not in plain and ":" not in plain, plain
    repl.command("@set printing_types true;")
    require(repl.command("42;"), "42 : Int")


def interrupt_and_eof(repl):
    repl.command("var saved=40;")
    os.kill(repl.process.pid, signal.SIGINT)
    interrupted = repl.read_prompt()
    print(interrupted, end="", flush=True)
    require(interrupted, "Caught interrupt")
    require(repl.command("saved+2;"), "42 : Int")
    repl.close(eof=True)


if __name__ == "__main__":
    cases = [definitions, polymorphism, alias_changes, environments, loading,
             imports, settings, printing, interrupt_and_eof]
    for case in cases:
        repl = Repl()
        try:
            print("\nCASE " + case.__name__, flush=True)
            print(repl.welcome, end="", flush=True)
            case(repl)
            repl.close()
            print("PASS " + case.__name__, flush=True)
        finally:
            repl.cleanup()
    print(str(len(cases)) + " contextual REPL cases passed", flush=True)
