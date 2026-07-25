# Stellogen Web Playground

A browser-based playground for experimenting with Stellogen code, compiled to JavaScript using js_of_ocaml.

The **Eval** button evaluates both phases (like `sgen eval`): the check
phase first, then the run phase only if it passed. **Run** and **Check**
evaluate a single phase each (like `sgen run` and `sgen check`), so you can
watch what phase separation actually skips. `§` items and `::` assertions
are verified in the browser too. Keyboard shortcuts: Ctrl+Enter to eval,
Ctrl+Shift+Enter to check.

## Building the Playground

### Prerequisites

Install the required OCaml packages:

```bash
opam install js_of_ocaml js_of_ocaml-compiler js_of_ocaml-ppx
```

### Build Steps

**Recommended: Use the build script**

```bash
# From the project root
./web/build.sh
```

This will:
1. Generate `examples.js` from `examples/*.sg` files
2. Compile OCaml to JavaScript
3. Copy all files to `web_deploy/`

**Manual build:**

1. **Generate examples:**

```bash
node web/build-examples.js
```

2. **Build the JavaScript file:**

```bash
# From the project root
dune build web/playground.bc.js
```

This will create:
- `_build/default/web/playground.bc.js` - The compiled JavaScript

3. **Copy files to serve:**

```bash
# Create a deploy directory
mkdir -p web_deploy
cp _build/default/web/playground.bc.js web_deploy/playground.js
cp web/index.html web_deploy/
cp web/worker.js web_deploy/
cp web/examples.js web_deploy/
```

4. **Serve locally (for testing):**

```bash
# Using Python
cd web_deploy
python3 -m http.server 8000

# Or using any other HTTP server
# Then open http://localhost:8000 in your browser
```

Note: the interpreter runs in a web worker (`worker.js`), which browsers
refuse to load from `file://` URLs. Always serve the playground over HTTP,
even for local testing.

### Examples Management

The playground loads examples from `web/examples.js`, which is **auto-generated** from the actual `examples/*.sg` files.

**To update examples:**

1. Edit the `.sg` files in `examples/`
2. Run `node web/build-examples.js` to regenerate `web/examples.js`
3. Or simply run `./web/build.sh` which includes this step

**Adding new examples:**

1. Create your `.sg` file in `examples/`
2. Add an entry to `EXAMPLE_MAPPING` in `web/build-examples.js`
3. Add a `<option>` tag in `web/index.html`
4. Rebuild: `node web/build-examples.js`

This approach eliminates duplication and ensures examples stay in sync with the source files.

## Development

### Testing Changes

After modifying `web_interface.ml` or `playground.ml`:

```bash
# Rebuild
dune build web/playground.bc.js

# Copy to deploy folder
cp _build/default/web/playground.bc.js web_deploy/playground.js

# Reload browser (hard refresh: Ctrl+Shift+R)
```

### Debugging

Open browser developer console (F12) to see:
- JavaScript errors
- `console.log()` output (add to `playground.ml`)
- Network requests

Add debug output in `playground.ml`:

```ocaml
let run_stellogen code_js =
  Firebug.console##log (Js.string "Running code...");
  (* ... *)
```

## Browser Compatibility

Tested on:
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

Requires:
- JavaScript enabled
- ~10 MB available memory

## Contributing

To add features to the playground:

1. Modify `src/web_interface.ml` for core functionality
2. Update `web/playground.ml` for JavaScript exports
3. Enhance `web/index.html` for UI improvements
4. Test in multiple browsers
5. Update this README

## License

Same as Stellogen: GPL-3.0-only
