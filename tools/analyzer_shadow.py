#!/usr/bin/env python3
"""Analyzer-shadow: catches missing-import / undefined-symbol errors for
PROJECT symbols (package:udao) without an SDK. Approximates what
`flutter analyze` reports as undefined_class / undefined_identifier /
uri_does_not_exist for our own code.

Heuristics (kept deliberately conservative to avoid noise):
  - only project symbols (declared in lib/ or test scaffolding) count;
    flutter/dart/external package names are ignored entirely.
  - occurrences preceded by `.` (member access) or followed by `:`
    (named arguments / labels) are not symbol references.
  - locally declared identifiers (params, vars, fields — crude but
    broad) never count as missing.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KEYWORDS = {
    'if', 'else', 'for', 'while', 'switch', 'case', 'default', 'return',
    'break', 'continue', 'new', 'const', 'final', 'var', 'late', 'async',
    'await', 'sync', 'yield', 'class', 'enum', 'typedef', 'extends',
    'implements', 'with', 'mixins', 'abstract', 'base', 'sealed', 'final',
    'static', 'get', 'set', 'this', 'super', 'null', 'true', 'false', 'in',
    'is', 'as', 'throw', 'try', 'catch', 'finally', 'do', 'when', 'show',
    'hide', 'on', 'of', 'part', 'library', 'export', 'import', 'dynamic',
    'void', 'Never', ' covariant', 'required', 'assert', 'operator',
}


def dart_files(base: str) -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [
            d for d in dirnames if d not in ('.git', '.dart_tool', 'build')
        ]
        for f in filenames:
            if f.endswith('.dart'):
                out.append(os.path.join(dirpath, f))
    return out


DECL_RE = re.compile(
    r'^(?:abstract\s+)?(?:base\s+)?(?:interface\s+)?(?:final\s+)?'
    r'(?:sealed\s+)?(?:mixin\s+)?(?:class|enum|typedef)\s+([A-Za-z_]\w*)',
    re.M,
)


def strip_comments(src: str) -> str:
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    return src


def strip_strings(src: str) -> str:
    """Blank out string literal CONTENTS (keeps quotes) so words inside
    strings never look like symbol references."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c in ('"', "'"):
            quote = c
            triple = src[i : i + 3] == quote * 3
            q = quote * 3 if triple else quote
            j = i + len(q)
            out.append(q)
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j : j + len(q)] == q:
                    break
                if not triple and src[j] == '\n':
                    break  # unterminated single-line string
                j += 1
            out.append(quote)
            i = j + len(q)
        elif c == 'r' and src[i + 1 : i + 2] in ('"', "'"):
            out.append('r')
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def top_level_names(path: str) -> set[str]:
    """Names visible when this file is imported (no `export` chains in
    this project; `show` on the CONSUMER side is handled separately)."""
    src = strip_strings(strip_comments(open(path, encoding='utf-8').read()))
    names = set(DECL_RE.findall(src))
    for line in src.splitlines():
        if line.startswith((' ', '\t', '//')):
            continue
        m = re.match(
            r'^(?:[A-Za-z_][\w<>,\s?]*?\s+)([a-z_]\w*)\s*[(=]', line
        )
        if m:
            names.add(m.group(1))
        m2 = re.match(r'^(?:const|final)\s+([A-Za-z_]\w*)\s*[=:]', line)
        if m2:
            names.add(m2.group(1))
    return names


def imports_of(path: str, src: str) -> list[tuple[str, list[str]]]:
    """[(resolved_target, [shown names] or [] meaning show-all)]"""
    out = []
    for m in re.finditer(
        r"^import\s+'([^']+)'\s*(?:as\s+\w+)?\s*(?:show\s+([\w,\s]+))?\s*;",
        src,
        re.M,
    ):
        target, shown = m.group(1), m.group(2)
        if target.startswith('package:udao/'):
            resolved = os.path.join(ROOT, 'lib', target[len('package:udao/'):])
        elif target.startswith('package:') or target.startswith('dart:'):
            continue
        else:
            resolved = os.path.normpath(
                os.path.join(os.path.dirname(path), target)
            )
        shown_list = (
            [s.strip() for s in shown.split(',')] if shown else None
        )
        out.append((resolved, shown_list))
    return out


def main() -> int:
    lib_files = dart_files(os.path.join(ROOT, 'lib'))
    test_files = dart_files(os.path.join(ROOT, 'test'))
    all_files = lib_files + test_files

    cache: dict[str, set[str]] = {}

    def names_of(p: str) -> set[str]:
        if p not in cache:
            cache[p] = top_level_names(p) if os.path.exists(p) else set()
        return cache[p]

    symtab: dict[str, set[str]] = {}
    for f in all_files:
        for n in names_of(f):
            symtab.setdefault(n, set()).add(
                os.path.relpath(f, ROOT).replace('\\', '/')
            )
    # lib/ files can only import lib/ symbols; test/ files may use both.
    lib_symtab = {
        n: fs
        for n, fs in symtab.items()
        if any(x.startswith('lib/') for x in fs)
    }

    problems = 0
    for f in sorted(all_files):
        rel = os.path.relpath(f, ROOT).replace('\\', '/')
        raw = open(f, encoding='utf-8').read()
        imports_src = strip_comments(raw)
        src = strip_strings(imports_src)

        # ---- 1. every project import target exists
        for target, _ in imports_of(f, imports_src):
            if not os.path.exists(target):
                print(f'FAIL-URI  {rel}: import target does not exist: {target}')
                problems += 1

        # ---- 2. symbol resolution
        available: set[str] = set()
        for target, shown in imports_of(f, imports_src):
            if shown is None:
                available |= names_of(target)
            else:
                available |= names_of(target) & set(shown)

        local_decl = names_of(f)
        # locally bound identifiers (params, locals, fields) — crude
        local_bound = set(
            re.findall(
                # lowerCamel only: `final Result<..> x` must NOT bind
                # `Result` as a local (phase-06 errata: that hole let
                # missing type imports through).
                r'\b(?:var|late)\s+([a-z_]\w*)\s*(?:[=;,)]|$)',
                src,
            )
        )
        local_bound |= set(
            re.findall(
                r'\b(?:final|const)\s+([a-z_]\w*)\s*(?:[=;,)]|$)', src
            )
        )
        local_bound |= set(
            re.findall(r'\b(?:[A-Za-z_]\w*)\s+([a-z_]\w*)\s*[),=]', src)
        )  # typed params like `int idx`, widget-builder params
        local_bound |= set(
            re.findall(r'\bthis\.([A-Za-z_]\w*)', src)
        )

        body = re.sub(r"^import\s+'[^']+'[^;]*;", '', src, flags=re.M)
        body = re.sub(r"^export\s+'[^']+'[^;]*;", '', body, flags=re.M)

        flagged: set[str] = set()
        for m in re.finditer(r'(\.?)([A-Za-z_]\w*)(\s*:?)', body):
            pre, name, post = m.groups()
            if pre == '.':
                continue  # member access — not a top-level reference
            if post.lstrip().startswith(':'):
                continue  # named argument / label
            if (
                name in KEYWORDS
                or name.startswith('_')
                or name in local_decl
                or name in available
                or name in local_bound
            ):
                continue
            table = symtab if rel.startswith('test/') else lib_symtab
            if name not in table:
                continue  # external / SDK symbol — not our problem
            flagged.add(name)

        for name in sorted(flagged):
            print(
                f'FAIL-SYM  {rel}: "{name}" used but not imported '
                f'(defined in {sorted(table[name])})'
            )
            problems += 1

    problems += check_required_params(all_files)

    print(f'\nanalyzer-shadow: {problems} problem(s)')
    return 1 if problems else 0




# ── required-named-param call-site check (errata-5 lesson) ─────────
def _class_bodies(src: str) -> dict[str, str]:
    """class name -> full declaration body (brace-matched)."""
    out: dict[str, str] = {}
    for m in re.finditer(
        r'class\s+([A-Z]\w*)[^{;]*\{', src
    ):
        name = m.group(1)
        i = m.end() - 1
        depth = 0
        j = i
        while j < len(src):
            if src[j] == '{':
                depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out[name] = src[i : j + 1]
    return out


REQ_RE = re.compile(r'required\s+([^,=\n]+)')


def _param_name(chunk: str) -> str | None:
    """`this.foo}` / `String path` / `Future<void> Function() clock` -> name.

    The LAST identifier token is the parameter name in every legal
    Dart declaration shape; trailing `})` junk is ignored by the
    token scan.
    """
    toks = re.findall(r'[A-Za-z_]\w*', chunk)
    if not toks:
        return None
    if chunk.strip().startswith('this.'):
        return toks[1] if len(toks) > 1 else None
    return toks[-1]


def check_required_params(files: list[str]) -> int:
    """Every `X(...)` call must pass every required named param of X.

    Catches the errata-5 class of bug: a constructor gains a required
    param, one call site is not updated, and nothing fails until the
    real analyzer runs on the user's machine.
    """
    req: dict[str, set[str]] = {}
    for f in files:
        raw = open(f, encoding='utf-8').read()
        for name, body in _class_bodies(strip_strings(raw)).items():
            # ONLY constructor parameter lists — method `required`
            # params are irrelevant to `X(...)` call sites.
            ctor_params = ''
            for cm in re.finditer(
                r'(?:^|\n)\s*(?:const\s+)?'
                + re.escape(name)
                + r'(?:\.[A-Za-z_]\w*)?\s*\(',
                body,
            ):
                i = cm.end()
                depth = 1
                j = i
                while j < len(body) and depth > 0:
                    if body[j] == '(':
                        depth += 1
                    elif body[j] == ')':
                        depth -= 1
                    j += 1
                ctor_params += body[i:j] + ','
            params = {
                n
                for n in (
                    _param_name(m.group(1))
                    for m in REQ_RE.finditer(ctor_params)
                )
                if n
            }
            if params:
                req.setdefault(name, set()).update(params)
    if not req:
        return 0
    problems = 0
    for f in files:
        raw = strip_strings(strip_comments(open(f, encoding='utf-8').read()))
        for m in re.finditer(r'\b([A-Z]\w*)\s*\(', raw):
            cls = m.group(1)
            if cls not in req or not req[cls]:
                continue
            pre = raw[max(0, m.start() - 24) : m.start()]
            if 'class ' in pre or 'extends ' in pre or 'implements ' in pre:
                continue  # declaration site, not a call
            i = m.end()
            depth = 1
            j = i
            while j < len(raw) and depth > 0:
                if raw[j] == '(':
                    depth += 1
                elif raw[j] == ')':
                    depth -= 1
                j += 1
            args = raw[i:j]
            if 'required ' in args or 'this.' in args:
                continue  # declaration body of a ctor, not a call
            # switch-arm / case / is-patterns: `X(:final a) => ...`
            # or `case X(...)` are PATTERNS, not constructor calls.
            after = raw[j : j + 8]
            if re.match(r'\s*=>', after) or re.search(
                r'(?:\bcase\s+|\bis\s+)$', pre
            ):
                continue
            if re.search(r':\s*(?:final\b|var\b)', args):
                continue
            for p in sorted(req[cls]):
                if not re.search(r'\b' + re.escape(p) + r'\s*:', args):
                    rel = os.path.relpath(f, ROOT).replace('\\', '/')
                    print(
                        f'FAIL-PARAM {rel}: call to {cls} is missing '
                        f'required named param `{p}:`'
                    )
                    problems += 1
    return problems
if __name__ == '__main__':
    sys.exit(main())
