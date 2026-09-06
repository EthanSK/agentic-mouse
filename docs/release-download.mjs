// Leave source/setup links usable when GitHub is offline or rate-limited.
export function releaseDownload(release, manifest) {
  if (!release || release.draft || release.prerelease || !manifest ||
      manifest.notarized !== true || manifest.stapled !== true ||
      !/^[0-9a-f]{64}$/.test(manifest.sha256 || '') ||
      !/^[0-9a-f]{40}$/.test(manifest.commit || '') ||
      !/^\d+\.\d+\.\d+$/.test(manifest.version || '') ||
      !Number.isSafeInteger(manifest.build) || manifest.build < 1 ||
      release.tag_name !== `v${manifest.version}-build.${manifest.build}`) return null;
  const name = `AgenticMouse-${manifest.version}-build.${manifest.build}-universal.zip`;
  if (manifest.archive !== name) return null;
  const url = `https://github.com/EthanSK/agentic-mouse/releases/download/${release.tag_name}/${name}`;
  return release.assets?.some(asset => asset.name === name && asset.browser_download_url === url) ? url : null;
}

export async function updateReleaseDownload(fetcher = fetch) {
  try {
    const response = await fetcher('https://api.github.com/repos/EthanSK/agentic-mouse/releases/latest', { signal: AbortSignal.timeout(5000) });
    if (!response.ok) return;
    const release = await response.json();
    const asset = release.assets?.find(item => item.name === 'release.json');
    if (!asset || !/^v\d+\.\d+\.\d+-build\.\d+$/.test(release.tag_name)) return;
    const url = `https://github.com/EthanSK/agentic-mouse/releases/download/${release.tag_name}/release.json`;
    if (asset.browser_download_url !== url) return;
    // GitHub release downloads do not promise browser CORS; the public release
    // body carries the same manifest inside a bounded marker for this read.
    const match = release.body?.match(/<!-- agentic-release (\{[^\n]+\}) -->/);
    if (!match) return;
    const download = releaseDownload(release, JSON.parse(match[1]));
    if (!download) return;
    const button = document.querySelector('[data-app-download]');
    if (!button) return;
    button.href = download;
    button.hidden = false;
    document.querySelector('.release-status').textContent = `Version ${release.tag_name.slice(1)} is signed and notarized. Setup still needs Karabiner and Accessibility permission. Corsair lighting needs the separate iCUE SDK.`;
  } catch { /* Keep the truthful pending state and working source links. */ }
}
if (typeof document !== 'undefined') updateReleaseDownload();
