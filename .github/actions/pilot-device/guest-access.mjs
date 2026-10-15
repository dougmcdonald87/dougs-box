const required = Object.freeze(['guestScreenVisible','guestInputConfirmed','guestReconnectConfirmed']);
export function evaluateGuestAccess(evidence = {}) {
  const missing = required.filter(key => evidence[key] !== true);
  if (evidence.attestation?.source !== 'independent-owner' || evidence.attestation?.validated !== true) missing.push('independentOwnerAttestation');
  return { ready: missing.length === 0, missing };
}
