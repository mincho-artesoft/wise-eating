import { createHash, createVerify, X509Certificate } from 'crypto';
import { decode } from 'cbor-x';

/**
 * Apple App Attest, following "Validating apps that connect to your server"
 * (developer.apple.com). Attestation proves a key lives in this app's Secure
 * Enclave on a genuine device; assertions prove later requests come from it.
 */

export class AppAttestError extends Error {}

const NONCE_OID = Buffer.from([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]);
const AAGUID_PRODUCTION = Buffer.concat([Buffer.from('appattest'), Buffer.alloc(7)]);
const AAGUID_DEVELOPMENT = Buffer.from('appattestdevelop');

export interface AttestationResult {
  publicKey: Buffer; // uncompressed P-256 point, 65 bytes
  keyId: string; // base64
  environment: 'production' | 'development';
}

export interface AuthenticatorData {
  rpIdHash: Buffer;
  flags: number;
  counter: number;
  aaguid?: Buffer;
  credentialId?: Buffer;
}

export function sha256(...parts: Buffer[]): Buffer {
  const h = createHash('sha256');
  for (const p of parts) h.update(p);
  return h.digest();
}

export function parseAuthenticatorData(data: Buffer): AuthenticatorData {
  if (data.length < 37) throw new AppAttestError('authenticator data too short');
  const rpIdHash = data.subarray(0, 32);
  const flags = data[32];
  const counter = data.readUInt32BE(33);
  if (data.length < 55) return { rpIdHash, flags, counter };
  const aaguid = data.subarray(37, 53);
  const idLength = data.readUInt16BE(53);
  const credentialId = data.subarray(55, 55 + idLength);
  return { rpIdHash, flags, counter, aaguid, credentialId };
}

/** The nonce inside Apple's credential certificate extension 1.2.840.113635.100.8.2. */
export function extractNonce(certificate: X509Certificate): Buffer {
  const raw = certificate.raw;
  const at = raw.indexOf(NONCE_OID);
  if (at < 0) throw new AppAttestError('nonce extension missing');
  // SEQUENCE { [1] { OCTET STRING (32) nonce } } inside the extension value.
  for (let i = at + NONCE_OID.length; i < Math.min(raw.length - 33, at + 64); i++) {
    if (raw[i] === 0x04 && raw[i + 1] === 0x20) return raw.subarray(i + 2, i + 34);
  }
  throw new AppAttestError('nonce not found in extension');
}

function uncompressedPoint(certificate: X509Certificate): Buffer {
  const spki = certificate.publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
  return spki.subarray(spki.length - 65);
}

export function appId(teamId: string, bundleId: string) {
  return `${teamId}.${bundleId}`;
}

/**
 * Verifies an attestation object for `keyId` made over `challenge`.
 * `rootPem` is Apple's App Attestation Root CA (injectable for tests).
 */
export function verifyAttestation(params: {
  attestation: Buffer;
  challenge: Buffer;
  keyId: string;
  appId: string;
  rootPem: string | Buffer;
  allowDevelopment: boolean;
  now?: Date;
}): AttestationResult {
  const object = decode(params.attestation) as { fmt?: string; attStmt?: { x5c?: Buffer[] }; authData?: Buffer };
  if (object?.fmt !== 'apple-appattest') throw new AppAttestError('unexpected format');
  const x5c = object.attStmt?.x5c;
  const authData = object.authData ? Buffer.from(object.authData) : undefined;
  if (!x5c || x5c.length < 2 || !authData) throw new AppAttestError('incomplete attestation');

  // 1. Certificate chain: credential cert <- intermediate <- Apple root.
  const credential = new X509Certificate(Buffer.from(x5c[0]));
  const intermediate = new X509Certificate(Buffer.from(x5c[1]));
  const root = new X509Certificate(params.rootPem);
  const now = params.now ?? new Date();
  for (const cert of [credential, intermediate]) {
    if (new Date(cert.validFrom) > now || new Date(cert.validTo) < now) throw new AppAttestError('certificate not valid now');
  }
  if (!credential.verify(intermediate.publicKey) || !credential.checkIssued(intermediate)) {
    throw new AppAttestError('credential certificate not issued by intermediate');
  }
  if (!intermediate.verify(root.publicKey) || !intermediate.checkIssued(root)) {
    throw new AppAttestError('intermediate not issued by Apple App Attestation root');
  }

  // 2-4. Nonce = SHA256(authData || SHA256(challenge)) must be in the certificate.
  const nonce = sha256(authData, sha256(params.challenge));
  if (!extractNonce(credential).equals(nonce)) throw new AppAttestError('nonce mismatch');

  // 5. The key id is the SHA256 of the public key.
  const publicKey = uncompressedPoint(credential);
  const keyIdBytes = Buffer.from(params.keyId, 'base64');
  if (!sha256(publicKey).equals(keyIdBytes)) throw new AppAttestError('key id mismatch');

  // 6-9. Authenticator data: our app, counter 0, Apple's aaguid, this key.
  const parsed = parseAuthenticatorData(authData);
  if (!parsed.rpIdHash.equals(sha256(Buffer.from(params.appId)))) throw new AppAttestError('app id mismatch');
  if (parsed.counter !== 0) throw new AppAttestError('counter must be 0');
  let environment: 'production' | 'development';
  if (parsed.aaguid?.equals(AAGUID_PRODUCTION)) environment = 'production';
  else if (parsed.aaguid?.equals(AAGUID_DEVELOPMENT) && params.allowDevelopment) environment = 'development';
  else throw new AppAttestError('unexpected aaguid');
  if (!parsed.credentialId?.equals(keyIdBytes)) throw new AppAttestError('credential id mismatch');

  return { publicKey, keyId: params.keyId, environment };
}

/** Builds an SPKI DER for an uncompressed P-256 point, for signature checks. */
export function p256Spki(point: Buffer): Buffer {
  const prefix = Buffer.from('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
  return Buffer.concat([prefix, point]);
}

/**
 * Verifies an assertion made with an attested key over `clientData`, and
 * returns the new counter (which must grow).
 */
export function verifyAssertion(params: {
  assertion: Buffer;
  clientData: Buffer;
  publicKey: Buffer;
  previousCounter: number;
  appId: string;
}): number {
  const object = decode(params.assertion) as { signature?: Buffer; authenticatorData?: Buffer };
  if (!object?.signature || !object.authenticatorData) throw new AppAttestError('incomplete assertion');
  const authData = Buffer.from(object.authenticatorData);
  const nonce = sha256(authData, sha256(params.clientData));
  const verifier = createVerify('SHA256');
  verifier.update(nonce);
  const ok = verifier.verify({ key: p256Spki(params.publicKey), format: 'der', type: 'spki' }, Buffer.from(object.signature));
  if (!ok) throw new AppAttestError('bad assertion signature');
  const parsed = parseAuthenticatorData(authData);
  if (!parsed.rpIdHash.equals(sha256(Buffer.from(params.appId)))) throw new AppAttestError('app id mismatch');
  if (parsed.counter <= params.previousCounter) throw new AppAttestError('assertion counter did not increase');
  return parsed.counter;
}
