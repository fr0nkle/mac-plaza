const origin = 'https://mac-plaza.tail1400d.ts.net';
// The permanent download links work independently of optional version metadata.
fetch(origin + '/releases/latest.json', {credentials:'omit', cache:'no-store', signal:AbortSignal.timeout(15000)})
  .then(response => {if (!response.ok) throw new Error('Unavailable');return response.json();})
  .then(release => {
    if (!/^\d+(\.\d+)*$/.test(release.version) || !release.files?.installer?.size) throw new Error('Invalid release');
    document.getElementById('release-status').textContent = `Version ${release.version} · ${Math.round(release.files.installer.size / 1048576)} MB · Installer + corresponding source`;
  })
  .catch(() => {
    document.getElementById('release-status').textContent = 'Latest preview · Installer includes corresponding source';
  });
