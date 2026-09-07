import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

// Substitute only the platform signing commands and network. Every upload goes to a
// private local fixture directory; this suite cannot reach Cloudflare or real credentials.
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'responsay-r2-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  const remote = join(root, 'remote');
  const output = join(root, 'build/release');
  for (const dir of [bin, remote, output, join(root, 'scripts')]) mkdirSync(dir, { recursive: true });
  assert.equal(spawnSync('git', ['init', '-q', root]).status, 0);
  const source = readFileSync(new URL('./publish-update-r2.sh', import.meta.url), 'utf8');
  writeFileSync(join(root, 'scripts/publish-update-r2.sh'), source.replaceAll('/usr/sbin/spctl', 'spctl'));
  const bytes = Buffer.from('synthetic dmg fixture');
  const digest = createHash('sha256').update(bytes).digest('hex');
  const checksum = `${digest}  Responsay.dmg\n`;
  writeFileSync(join(output, 'Responsay.dmg'), bytes);
  writeFileSync(join(output, 'Responsay.dmg.sha256'), checksum);
  const feed = (build = 158, url = 'https://updates.responsay.com/releases/v1.9.3/Responsay.dmg') =>
    `<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>${build}</sparkle:version><sparkle:shortVersionString>1.9.3</sparkle:shortVersionString><enclosure url="${url}" length="${bytes.length}" sparkle:edSignature="synthetic-signature" type="application/octet-stream" /></item></channel></rss>`;
  writeFileSync(join(output, 'appcast.xml'), feed());
  writeFileSync(join(root, 'appcast.xml'), feed());
  const executable = (name, text) => writeFileSync(join(bin, name), text, { mode: 0o755 });
  executable('spctl', '#!/bin/sh\nexit 0\n');
  executable('xcrun', '#!/bin/sh\nexit 0\n');
  executable('curl', `#!/usr/bin/env python3
import os, sys, pathlib, urllib.parse
args=sys.argv[1:]; url=next(a for a in args if a.startswith('https://'))
p=pathlib.Path(os.environ['FIXTURE_REMOTE']) / urllib.parse.urlparse(url).path.lstrip('/')
found=p.is_file()
# Model the edge caching a bare missing artifact URL even after an upload.
negative=pathlib.Path(os.environ['FIXTURE_REMOTE'])/('.cached-missing-'+p.name)
if p.suffix in ('.dmg', '.sha256') and not urllib.parse.urlparse(url).query:
    if negative.exists(): found=False
    elif not found: negative.touch()
if '-o' in args: pathlib.Path(args[args.index('-o')+1]).write_bytes(p.read_bytes() if found else b'not found')
if '-w' in args: print('200' if found else '404',end='')
if not found and any(a.startswith('-') and 'f' in a for a in args): sys.exit(22)
`);
  executable('wrangler', `#!/usr/bin/env python3
import os, sys, pathlib, shutil
args=sys.argv[1:]; key=args[3].split('/',1)[1]
p=pathlib.Path(os.environ['FIXTURE_REMOTE'])/key; p.parent.mkdir(parents=True,exist_ok=True)
src=next(a.split('=',1)[1] for a in args if a.startswith('--file=')); shutil.copyfile(src,p)
with open(os.environ['FIXTURE_UPLOADS'],'a') as f: f.write(key+'\\n')
`);
  return { root, remote, output, bytes, checksum, feed,
    run: (phase = 'artifacts') => spawnSync('bash', ['scripts/publish-update-r2.sh', phase, 'v1.9.3'], {
      cwd: root, encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}`,
        RESPONSAY_WRANGLER: join(bin, 'wrangler'), RESPONSAY_R2_BUCKET: 'fixture',
        RESPONSAY_UPDATE_BASE_URL: 'https://updates.responsay.com',
        FIXTURE_REMOTE: remote, FIXTURE_UPLOADS: join(root, 'uploads') },
    }),
  };
}

test('publishes the verified feed last', t => {
  const f = fixture(t);
  assert.equal(f.run().status, 0);
  const result = f.run('activate');
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.deepEqual(readFileSync(join(f.root, 'uploads'), 'utf8').trim().split('\n'), ['releases/v1.9.3/Responsay.dmg', 'releases/v1.9.3/Responsay.dmg.sha256', 'Responsay.dmg', 'Responsay.dmg.sha256', 'appcast.xml']);
});

test('rejects same-build feed with a different enclosure before any upload', t => {
  const f = fixture(t);
  writeFileSync(join(f.root, 'appcast.xml'), f.feed(158, 'https://example.invalid/wrong.dmg'));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /release metadata differs/);
  assert.equal(existsSync(join(f.root, 'uploads')), false);
});

test('rejects republishing an older build over a newer live feed', t => {
  const f = fixture(t); writeFileSync(join(f.remote, 'appcast.xml'), f.feed(159));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /newer live build/);
  assert.equal(existsSync(join(f.root, 'uploads')), false);
  assert.equal(readFileSync(join(f.remote, 'appcast.xml'), 'utf8'), f.feed(159));
});

test('repairs a missing versioned checksum when retrying a completed DMG upload', t => {
  const f = fixture(t); const dir = join(f.remote, 'releases/v1.9.3'); mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'Responsay.dmg'), f.bytes);
  const result = f.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(readFileSync(join(dir, 'Responsay.dmg.sha256'), 'utf8'), f.checksum);
});

test('rejects an enclosure length that does not match the DMG', t => {
  const f = fixture(t); const invalid = f.feed().replace(`length="${f.bytes.length}"`, 'length="999"');
  writeFileSync(join(f.root, 'appcast.xml'), invalid);
  writeFileSync(join(f.output, 'appcast.xml'), invalid);
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /length does not match DMG/);
  assert.equal(existsSync(join(f.root, 'uploads')), false);
});

test('rejects conflicting metadata for an already live build', t => {
  const f = fixture(t);
  writeFileSync(join(f.remote, 'appcast.xml'), f.feed().replace('synthetic-signature', 'other-signature'));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /already exists with different release metadata/);
  assert.equal(existsSync(join(f.root, 'uploads')), false);
});

test('allows an exact retry of the current live build', t => {
  const f = fixture(t);
  assert.equal(f.run().status, 0);
  assert.equal(f.run('activate').status, 0);
  const result = f.run('activate');
  assert.equal(result.status, 0, result.stdout + result.stderr);
});


test('artifacts phase leaves stable downloads and feeds untouched', t => {
  const f = fixture(t);
  writeFileSync(join(f.remote, 'appcast.xml'), f.feed(157));
  writeFileSync(join(f.remote, 'Responsay.dmg'), 'old stable download');
  const result = f.run();
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(readFileSync(join(f.remote, 'appcast.xml'), 'utf8'), f.feed(157));
  assert.equal(readFileSync(join(f.remote, 'Responsay.dmg'), 'utf8'), 'old stable download');
  assert.deepEqual(readFileSync(join(f.root, 'uploads'), 'utf8').trim().split('\n'), ['releases/v1.9.3/Responsay.dmg', 'releases/v1.9.3/Responsay.dmg.sha256']);
});

for (const missing of ['DMG', 'checksum']) {
  test(`activation refuses a missing immutable ${missing} before any write`, t => {
    const f = fixture(t);
    if (missing === 'checksum') {
      const dir = join(f.remote, 'releases/v1.9.3'); mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, 'Responsay.dmg'), f.bytes);
    }
    const result = f.run('activate');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /is missing; run artifacts before activating/);
    assert.equal(existsSync(join(f.root, 'uploads')), false);
  });
}
