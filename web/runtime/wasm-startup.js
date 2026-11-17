if (!globalThis.process?.versions?.node && globalThis.addEventListener) {
  globalThis.addEventListener("unhandledrejection", event => {
    globalThis.postMessage({
      kind: "failure",
      stage: "startup",
      diagnostic: String(event.reason?.message ?? event.reason),
    });
    event.preventDefault();
  });
}
