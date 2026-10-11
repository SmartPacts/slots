// crank-keygen.mjs — create the crank's signing key ON THE MACHINE THAT WILL RUN IT, and refuse to
// overwrite one that already exists.
//
// Same shape as the prize-draw crank's keygen, for the same reasons: overwriting a funded key file
// loses control of whatever that account holds, permanently, so this never does it. The existence
// check is backed by an exclusive-create write ('wx'), which also fails if a file appears between
// the check and the write. The file is 0600 inside a 0700 directory. Only the PUBLIC key and the
// account are printed; the secret never leaves the file, and never appears in a log, a terminal
// scrollback or a message to anyone.
//
//   node crank-keygen.mjs /etc/<game>/crank-key.json
//
// One key per game per machine: each game's crank pays its own gas from its own account, so one
// game's spending can never starve another's.
//
// It lives beside game-crank.mjs because it shares the crank's dependencies: run it from there.
//
// The file it writes is the FLAT shape the crank reads — {account, publicKey, secretKey} at the
// top level, no persona wrapper — so the service runs with
//   CRANK_BOT_KEY=/etc/<game>/crank-key.json
// (roulette-crank.mjs, the single-game crank that game-crank.mjs replaces, reads the same file as ROULETTE_BOT_KEY).
//
// FUND IT AFTERWARDS. The account printed here holds nothing when it is created. Send it a small
// amount of KDA on the table's chain (chain 2) once the machine is set up — game-crank.mjs's
// header puts the whole duty at about 1 KDA a year on a busy table, the paying half of it 0.812
// KDA a year at 500 winners a day. Nothing else about this key is privileged: the crank holds no
// authority over any round, earns nothing, and every call it makes is one anybody could make.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { genKeyPair } from '@kadena/cryptography-utils';

const target = process.argv[2];
if (!target) {
  console.error('usage: node crank-keygen.mjs <path/to/crank-key.json>   (the service reads it as CRANK_BOT_KEY)');
  process.exit(2);
}
const path = resolve(target);
if (existsSync(path)) {
  console.error(`REFUSING: ${path} already exists. Overwriting a key file loses control of the account it funds.`);
  console.error('Move it aside yourself if you are certain it holds nothing, then run this again.');
  process.exit(1);
}
const kp = genKeyPair();
if (!kp.secretKey || !/^[0-9a-f]{64}$/.test(kp.publicKey)) {
  console.error('key generation returned an unexpected shape; nothing was written');
  process.exit(1);
}
mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
writeFileSync(
  path,
  JSON.stringify({ account: `k:${kp.publicKey}`, publicKey: kp.publicKey, secretKey: kp.secretKey }, null, 2) + '\n',
  { mode: 0o600, flag: 'wx' },
);
console.log(`key file   : ${path} (mode 0600)`);
console.log(`public key : ${kp.publicKey}`);
console.log(`account    : k:${kp.publicKey}`);
console.log('');
console.log("FUND THAT ACCOUNT on the table's chain (chain 2), then enable the service. Until it holds");
console.log('KDA the crank can read the chain but cannot pay for a single transaction.');
