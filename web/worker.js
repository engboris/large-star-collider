// Web worker: runs the Stellogen interpreter off the main thread, so the
// page stays responsive and diverging programs can be terminated from
// index.html instead of freezing the tab.
//
// The interpreter is loaded with a revalidating fetch instead of a plain
// importScripts('playground.js'): scripts imported inside a worker stay in
// the HTTP cache even across page reloads, so redeploys kept serving a
// stale interpreter. 'no-cache' still answers from the cache when the
// server replies 304, so this costs one conditional request per worker
// start, not a full download.
const ready = fetch('playground.js', { cache: 'no-cache' })
  .then((resp) => {
    if (!resp.ok) throw new Error('failed to load playground.js (HTTP ' + resp.status + ')');
    return resp.text();
  })
  .then((src) => {
    const url = URL.createObjectURL(new Blob([src], { type: 'text/javascript' }));
    importScripts(url);
    URL.revokeObjectURL(url);
  });

self.onmessage = async (e) => {
  const { id, mode, code } = e.data;
  try {
    await ready;
    // 'eval' is the default: both phases, like the sgen command
    const result =
      mode === 'check' ? Stellogen.check(code) :
      mode === 'run' ? Stellogen.run(code) :
      Stellogen.eval(code);
    self.postMessage({ id, result });
  } catch (err) {
    // "ERROR: " prefix is how index.html recognizes failures
    self.postMessage({ id, result: 'ERROR: ' + (err && err.message ? err.message : err) });
  }
};
