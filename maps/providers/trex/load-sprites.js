// Paste in CloudTAK map page DevTools after the map is up.
// Expects sprites fetched to maps/data/sprites/ and served at /pmtiles/sprites/topo-print
// Proprietary T.REX ARMS assets — local deploy only.
(async () => {
  const base = `${location.origin}/pmtiles/sprites/topo-print`;
  const meta = await (await fetch(`${base}.json`)).json();
  const bmp = await createImageBitmap(await (await fetch(`${base}.png`)).blob());
  const map = window.__map || window.map;
  if (!map || !map.addImage) {
    throw new Error('Expose the MapLibre map as window.__map first');
  }
  for (const [id, s] of Object.entries(meta)) {
    const c = document.createElement('canvas');
    c.width = s.width;
    c.height = s.height;
    c.getContext('2d').drawImage(bmp, s.x, s.y, s.width, s.height, 0, 0, s.width, s.height);
    const data = c.getContext('2d').getImageData(0, 0, s.width, s.height);
    if (!map.hasImage(id)) map.addImage(id, data, { pixelRatio: s.pixelRatio || 1 });
  }
  console.log('loaded', Object.keys(meta).length, 'T.Rex sprite icons');
})();
