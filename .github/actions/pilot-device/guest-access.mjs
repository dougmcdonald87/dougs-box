const required = Object.freeze(['guestScreenVisible','guestInputConfirmed','guestReconnectConfirmed']);

/** Pure acceptance check; values must be independent, externally verified booleans. */
export function evaluateGuestAccess(evidence = {}) {
  const missing = required.filter(key => evidence[key] !== true);
  return { ready: missing.length === 0, missing };
}
