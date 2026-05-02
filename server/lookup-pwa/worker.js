// Web Worker: brute-force TagID x Slot through AES-128 ECB.
//
// Current model:
//   - operator UUID is static and checked outside the worker
//   - worker resolves only our operator packets
//   - one AES block per candidate:
//       ECB(KEY, [tagID(2)|slot(4)|0x00(10)]) -> Major(2)+Minor(2)+MAC(6)
//
// AES-ECB is implemented through AES-CBC with zero IV:
//   CBC(key, iv=0, block) == ECB(key, block) for a single block.

let cryptoKey = null;

async function importKey(keyBytes) {
  cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "AES-CBC" },
    false,
    ["encrypt"]
  );
}

function buildBlock(tagID, slot) {
  const block = new Uint8Array(16);
  block[0] = (tagID >> 8) & 0xff;
  block[1] = tagID & 0xff;
  block[2] = (slot >> 24) & 0xff;
  block[3] = (slot >> 16) & 0xff;
  block[4] = (slot >> 8) & 0xff;
  block[5] = slot & 0xff;
  return block;
}

async function aesECB(block) {
  const iv = new Uint8Array(16);
  const ct = await crypto.subtle.encrypt({ name: "AES-CBC", iv }, cryptoKey, block);
  return new Uint8Array(ct, 0, 16);
}

async function searchBySum({ keyHex, idSum, tagMin, tagMax, slotMin, slotMax }) {
  const keyBytes = new Uint8Array(keyHex.match(/.{2}/g).map((b) => parseInt(b, 16)));
  await importKey(keyBytes);

  const total = (tagMax - tagMin + 1) * (slotMax - slotMin + 1);
  let checked = 0;
  let lastReport = Date.now();

  for (let tagID = tagMin; tagID <= tagMax; tagID++) {
    for (let slot = slotMin; slot <= slotMax; slot++) {
      const out = await aesECB(buildBlock(tagID, slot));
      const major = (out[0] << 8) | out[1];
      const minor = (out[2] << 8) | out[3];

      if (major + minor === idSum) {
        const mac = [
          out[4] | 0xc0, out[5], out[6], out[7], out[8], out[9]
        ].map((b) => b.toString(16).padStart(2, "0").toUpperCase()).join(":");

        self.postMessage({ type: "found", tagID, slot, mac, checked });
        return;
      }

      checked++;
      const now = Date.now();
      if (now - lastReport > 200) {
        self.postMessage({ type: "progress", checked, total });
        lastReport = now;
      }
    }
  }

  self.postMessage({ type: "notfound", checked });
}

async function search({ keyHex, major, minor, tagMin, tagMax, slotMin, slotMax }) {
  const keyBytes = new Uint8Array(keyHex.match(/.{2}/g).map((b) => parseInt(b, 16)));
  await importKey(keyBytes);

  const total = (tagMax - tagMin + 1) * (slotMax - slotMin + 1);
  let checked = 0;
  let lastReport = Date.now();

  for (let tagID = tagMin; tagID <= tagMax; tagID++) {
    for (let slot = slotMin; slot <= slotMax; slot++) {
      const out = await aesECB(buildBlock(tagID, slot));
      const calcMajor = (out[0] << 8) | out[1];
      const calcMinor = (out[2] << 8) | out[3];

      if (calcMajor === major && calcMinor === minor) {
        const mac = [
          out[4] | 0xc0, out[5], out[6], out[7], out[8], out[9]
        ].map((b) => b.toString(16).padStart(2, "0").toUpperCase()).join(":");

        self.postMessage({ type: "found", tagID, slot, mac, checked });
        return;
      }

      checked++;
      const now = Date.now();
      if (now - lastReport > 200) {
        self.postMessage({ type: "progress", checked, total });
        lastReport = now;
      }
    }
  }

  self.postMessage({ type: "notfound", checked });
}

self.onmessage = async (event) => {
  try {
    if (event.data.mode === "sum") {
      await searchBySum(event.data);
    } else {
      await search(event.data);
    }
  } catch (error) {
    self.postMessage({ type: "error", message: error.message });
  }
};
