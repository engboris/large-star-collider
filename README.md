# Stellogen

**A programming language where computation and types are built from the same mechanism: term unification.**

![Status: Experimental](https://img.shields.io/badge/status-experimental-orange)
![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)
![OCaml](https://img.shields.io/badge/built_with-OCaml-ec6813)

Stellogen is a research language exploring what programming looks like without
primitive types or fixed logical rules, just elementary interactive building
blocks based on **term unification**.

**Status**: Experimental proof of concept / Research project / Esoteric language (not production-ready)

---

## Why Stellogen?

Traditional typed languages use types to constrain programs and ensure
correctness. Types act as **questions**, programs as **answers**. This is
powerful but also constraining, it defines which questions you can even ask.

**Stellogen explores a different path**:
- Computation and typing use the same mechanism (term unification)
- No primitive types or fixed logic imposed from above
- The compiler only checks that blocks connect: **semantic power belongs to you**

This shifts responsibility from the language designer to the user. With that
power comes the need for discipline, but also the freedom to explore
computational models that don't fit traditional type systems.

### Influences

Stellogen draws inspiration from:
- **Prolog/Datalog** - Unification and logic programming
- **Smalltalk** - Minimalism and message-passing
- **Rocq (Coq)** - Proof-as-program paradigm
- **Scheme/Racket** - Metaprogramming philosophy
- **Shen** - Optional type systems and user responsibility
- **Girard's Transcendental Syntax** - Theoretical foundation

## What Makes Stellogen Different?

- **No primitive types** - Types are user-defined as sets of interactive tests
- **Unification everywhere** - The same mechanism handles both computation and type checking
- **Logic-agnostic** - Build your own logic rather than conforming to one imposed by the language
- **Multi-paradigm** - Express logic programming, functional, imperative, or OO styles using the same underlying mechanism

Stellogen's constellation-based model supports multiple programming paradigms:

| Paradigm        | Stellogen Equivalent                                     |
| --------------- | -------------------------------------------------------- |
| Logic           | Constellations (elementary blocks)                       |
| Functional      | Layered constellations enforcing order of interaction    |
| Imperative      | Iterative recipes for building constellations            |
| Object-oriented | Structured constellations                                |

---

## Quick Example

```stellogen
; Define variable x as positive first-order term +f(a)
(def x (+f a))

; Define variable y as block of terms containing +f(X) and X
(def y [(-f X) X])

; Display [(-f X) X] on screen
(show #y)

; Make x and y interact along (+f a) and (-f X)
; The conflict is resolved and propagated to the other term X
; It results in [a]
(def result (exec #x #y))

; Display result [a] on screen
(show #result)
```

---

## Getting Started

### 1. Install

**Option A: Download Binary** (fastest)
- Get the latest release from [Releases](https://github.com/engboris/stellogen/releases)
then put the executable in your PATH as `sgen`.

**Option B: Install via opam** (up-to-date and more convenient)
```bash
opam pin stellogen https://github.com/engboris/stellogen.git
# The command sgen is directly accessible from your PATH
```

**Option C: Build from Source**
```bash
# Install dependencies
opam install . --deps-only --with-test

# Build
dune build

# Executable will be in _build/default/bin/
# You can put it in your PATH for more convenience
```

**Option D: Build with Nix**
```bash
nix build

```
If you wish, you can explicitly specify the derivation, like `nix build .#default`:
- `default`/`stellogen`: The default binary
- `stellogen-minimal`: Minimal version without documentation and JavaScript
- `stellogen-web`: JavaScript version
- `playground`: Playground files you can host with e.g. `python3 -m http.server` or directly with `nix run .#playground`
- `docs`: Documentation
### 2. Run Your First Program

Assuming the executable is named `sgen` and that it is in your PATH:

```bash
sgen run examples/hello.sg
```

### 3. Learn the Basics

- **Quick tutorial**: https://github.com/engboris/stellogen/wiki/Basics-of-Stellogen
- **Examples**: Explore [`examples/`](examples/) directory

---

## Commands

Stellogen provides four main commands:

### `run` - Execute a Program

Run a Stellogen program:

```bash
sgen run <filename>
```

**Example**:
```bash
sgen run examples/hello.sg
```

### `preprocess` - View Preprocessed Code

Show how macros expand and code is preprocessed:

```bash
sgen preprocess <filename>
```

Useful for debugging macro expansions and understanding how syntactic sugar is desugared.

### `trace` - Interactive Execution Trace

Step through program execution and visualize how stars interact:

```bash
sgen trace <filename>
```

Shows each fusion step with visual arrows pointing to the exact rays being connected. Press Enter to advance through each step.

For re-running on file changes during development, use a general-purpose
watcher such as `entr` or `watchexec`, e.g. `ls myprogram.sg | entr sgen run
myprogram.sg`.

---

**Ready to explore?** Dive into the [Quick Tutorial](https://github.com/engboris/stellogen/wiki/Basics-of-Stellogen)!
