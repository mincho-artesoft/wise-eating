import { encode } from 'cbor-x';
import { createSign, generateKeyPairSync, randomBytes } from 'crypto';
import { execFileSync } from 'child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { AppAttestError, sha256, verifyAssertion, verifyAttestation } from '../src/devices/app-attest';

const APP_ID = 'TEAMID1234.com.example.ayura';

function authData(counter: number, credentialId?: Buffer, aaguid = Buffer.from('appattestdevelop')) {
  const head = Buffer.alloc(37);
  sha256(Buffer.from(APP_ID)).copy(head, 0);
  head[32] = 0x41;
  head.writeUInt32BE(counter, 33);
  if (!credentialId) return head;
  const len = Buffer.alloc(2);
  len.writeUInt16BE(credentialId.length);
  return Buffer.concat([head, aaguid, len, credentialId]);
}

function point(publicKeyDer: Buffer) {
  return publicKeyDer.subarray(publicKeyDer.length - 65);
}

/**
 * A stand-in for Apple's chain made with openssl: our own root and
 * intermediate, and a credential certificate carrying the nonce extension,
 * so the full verification path runs.
 */
function makeAttestation(challenge: Buffer) {
  const dir = mkdtempSync(join(tmpdir(), 'attest-'));
  try {
    const key = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const spki = key.publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
    const keyId = sha256(point(spki));
    const data = authData(0, keyId);
    const nonce = sha256(data, sha256(challenge));
    const ossl = (...args: string[]) => execFileSync('openssl', args, { cwd: dir, stdio: 'pipe' });
    ossl('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'root.key');
    ossl('req', '-x509', '-new', '-key', 'root.key', '-subj', '/CN=Test Attestation Root', '-days', '2', '-out', 'root.pem',
      '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign');
    ossl('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', 'int.key');
    ossl('req', '-new', '-key', 'int.key', '-subj', '/CN=Test Attestation CA 1', '-out', 'int.csr');
    writeFileSync(join(dir, 'int.ext'), 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n');
    ossl('x509', '-req', '-in', 'int.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '2', '-extfile', 'int.ext', '-out', 'int.pem');
    writeFileSync(join(dir, 'leaf.key'), key.privateKey.export({ format: 'pem', type: 'pkcs8' }));
    ossl('req', '-new', '-key', 'leaf.key', '-subj', '/CN=leaf', '-out', 'leaf.csr');
    const ext = `1.2.840.113635.100.8.2=DER:3024a1220420${nonce.toString('hex')}\n`;
    writeFileSync(join(dir, 'leaf.ext'), ext);
    ossl('x509', '-req', '-in', 'leaf.csr', '-CA', 'int.pem', '-CAkey', 'int.key', '-CAcreateserial', '-days', '2', '-extfile', 'leaf.ext', '-outform', 'DER', '-out', 'leaf.der');
    ossl('x509', '-in', 'int.pem', '-outform', 'DER', '-out', 'int.der');
    const attestation = encode({
      fmt: 'apple-appattest',
      attStmt: { x5c: [readFileSync(join(dir, 'leaf.der')), readFileSync(join(dir, 'int.der'))], receipt: Buffer.alloc(0) },
      authData: data,
    });
    return { attestation: Buffer.from(attestation), keyId: keyId.toString('base64'), root: readFileSync(join(dir, 'root.pem')), privateKey: key.privateKey };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe('App Attest', () => {
  it('verifies a well-formed attestation and rejects a different challenge or app', () => {
    const challenge = randomBytes(32);
    const made = makeAttestation(challenge);
    const result = verifyAttestation({ attestation: made.attestation, challenge, keyId: made.keyId, appId: APP_ID, rootPem: made.root, allowDevelopment: true });
    expect(result.environment).toBe('development');
    expect(result.publicKey.length).toBe(65);

    expect(() => verifyAttestation({ attestation: made.attestation, challenge: randomBytes(32), keyId: made.keyId, appId: APP_ID, rootPem: made.root, allowDevelopment: true })).toThrow(AppAttestError);
    expect(() => verifyAttestation({ attestation: made.attestation, challenge, keyId: made.keyId, appId: 'OTHER.app', rootPem: made.root, allowDevelopment: true })).toThrow(AppAttestError);
    // Development keys are refused in production.
    expect(() => verifyAttestation({ attestation: made.attestation, challenge, keyId: made.keyId, appId: APP_ID, rootPem: made.root, allowDevelopment: false })).toThrow(/aaguid/);
    // Apple's real root does not sign the test chain.
    const appleRoot = readFileSync(join(__dirname, '..', 'certs', 'Apple_App_Attestation_Root_CA.pem'));
    expect(() => verifyAttestation({ attestation: made.attestation, challenge, keyId: made.keyId, appId: APP_ID, rootPem: appleRoot, allowDevelopment: true })).toThrow(/root/);
  });

  it('verifies assertions and refuses replays', () => {
    const key = generateKeyPairSync('ec', { namedCurve: 'P-256' });
    const pub = point(key.publicKey.export({ format: 'der', type: 'spki' }) as Buffer);
    const clientData = Buffer.from('challenge-123');
    const assertion = (counter: number) => {
      const data = authData(counter);
      const nonce = sha256(data, sha256(clientData));
      const signer = createSign('SHA256');
      signer.update(nonce);
      return Buffer.from(encode({ signature: signer.sign(key.privateKey), authenticatorData: data }));
    };
    expect(verifyAssertion({ assertion: assertion(1), clientData, publicKey: pub, previousCounter: 0, appId: APP_ID })).toBe(1);
    expect(() => verifyAssertion({ assertion: assertion(1), clientData, publicKey: pub, previousCounter: 1, appId: APP_ID })).toThrow(/counter/);
    expect(() => verifyAssertion({ assertion: assertion(2), clientData: Buffer.from('other'), publicKey: pub, previousCounter: 1, appId: APP_ID })).toThrow(/signature/);
  });
});
