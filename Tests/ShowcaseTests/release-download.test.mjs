import test from 'node:test';
import assert from 'node:assert/strict';
import { releaseDownload } from '../../docs/release-download.mjs';
const manifest = { version: '1.2.3', build: 8, notarized: true, stapled: true, sha256: 'a'.repeat(64), commit: 'b'.repeat(40), archive: 'AgenticMouse-1.2.3-build.8-universal.zip' };
const url = 'https://github.com/EthanSK/agentic-mouse/releases/download/v1.2.3-build.8/AgenticMouse-1.2.3-build.8-universal.zip';
const release = { tag_name: 'v1.2.3-build.8', assets: [{ name: manifest.archive, browser_download_url: url }] };
test('only a published notarized version with its exact asset offers a download', () => {
  assert.equal(releaseDownload(release, manifest), url);
  for (const key of ['draft', 'prerelease']) assert.equal(releaseDownload({ ...release, [key]: true }, manifest), null);
  for (const key of ['notarized', 'stapled']) assert.equal(releaseDownload(release, { ...manifest, [key]: false }), null);
  assert.equal(releaseDownload({ ...release, assets: [] }, manifest), null);
  assert.equal(releaseDownload({ ...release, tag_name: 'v1.2.4-build.8' }, manifest), null);
  assert.equal(releaseDownload({ ...release, assets: [{ name: manifest.archive, browser_download_url: 'https://example.com/app.zip' }] }, manifest), null);
  assert.equal(releaseDownload(release, { ...manifest, archive: '../app.zip' }), null);
});
