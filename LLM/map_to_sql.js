// map_to_sql.js
// Convert enriched room graph JSON (rooms + directed links) into SQL INSERTs for `rooms`.
// Exits are derived (reciprocals added) and ordered as nsweud.
//
// Usage:
// node map_to_sql.js \
//   --in enriched_map.json \
//   --zone_id 2 \
//   --created_by 1 \
//   --start_x 700 --start_y 700 --start_z 100 \
//   --out rooms_inserts.sql
//
// node map_to_sql.js --in enriched_map.json --zone_id 2 --created_by 1 --out rooms.sql
// Optional: --start_x 700 --start_y 700 --start_z 100
//
// Notes:
// - Room ids are R001..R###; we map them to actual DB ids by insertion order.
// - If coordinate constraints conflict, we keep the first assigned position and report conflicts.
// - You can set x/y/z to NULL if you prefer by adding --no_coords.

const fs = require("fs");

const ORDER = ["n", "s", "w", "e", "u", "d"];
const OPP = { n: "s", s: "n", w: "e", e: "w", u: "d", d: "u" };
const DELTA = {
  n: [0, 1, 0],
  s: [0, -1, 0],
  w: [-1, 0, 0],
  e: [1, 0, 0],
  u: [0, 0, 1],
  d: [0, 0, -1],
};

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (!a.startsWith("--")) continue;
    const key = a.slice(2);
    const next = args[i + 1];
    if (next && !next.startsWith("--")) {
      out[key] = next;
      i++;
    } else {
      out[key] = true;
    }
  }
  return out;
}

function sqlEscape(val) {
  if (val === null || val === undefined) return "NULL";
  if (typeof val === "number") return Number.isFinite(val) ? String(val) : "NULL";
  // string
  const s = String(val)
    .replace(/\\/g, "\\\\")
    .replace(/\u0000/g, "\\0")
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t")
    .replace(/'/g, "''");
  return `'${s}'`;
}

function roomKey(from, dir) {
  return `${from}:${dir}`;
}

function validateInput(data) {
  if (!data || typeof data !== "object") throw new Error("Input JSON must be an object.");
  if (!Array.isArray(data.rooms) || !Array.isArray(data.links)) {
    throw new Error("Input JSON must have arrays: rooms, links.");
  }
  for (const r of data.rooms) {
    if (!r.id) throw new Error("Each room must have an id.");
  }
  for (const l of data.links) {
    if (!l.from || !l.to || !l.dir) throw new Error("Each link must have from, dir, to.");
    if (!OPP[l.dir]) throw new Error(`Invalid link dir: ${l.dir}`);
  }
}

function buildExpandedLinks(links) {
  const expanded = [];
  for (const l of links) expanded.push({ from: l.from, dir: l.dir, to: l.to });
  for (const l of links) expanded.push({ from: l.to, dir: OPP[l.dir], to: l.from });
  return expanded;
}

function buildExitsByRoom(roomIds, expandedLinks) {
  const exits = {};
  const toByFromDir = new Map();

  for (const id of roomIds) exits[id] = new Set();

  for (const l of expandedLinks) {
    const k = roomKey(l.from, l.dir);
    if (toByFromDir.has(k) && toByFromDir.get(k) !== l.to) {
      // Conflict: same from+dir points to two different rooms
      // We'll keep the first and ignore later.
      continue;
    }
    toByFromDir.set(k, l.to);
    exits[l.from]?.add(l.dir);
  }

  const exitsString = {};
  for (const id of roomIds) {
    exitsString[id] = ORDER.filter(d => exits[id].has(d)).join("");
  }

  return { exitsString, toByFromDir };
}

function assignCoordinates(roomIds, toByFromDir, startX, startY, startZ) {
  // BFS embedding: assign positions consistent with directions when possible.
  // If a room already has a position and a new constraint disagrees, record conflict.
  const pos = new Map(); // id -> [x,y,z]
  const conflict = [];

  const start = roomIds[0];
  pos.set(start, [startX, startY, startZ]);

  const q = [start];
  const seen = new Set([start]);

  while (q.length) {
    const cur = q.shift();
    const [cx, cy, cz] = pos.get(cur);

    for (const dir of ORDER) {
      const to = toByFromDir.get(roomKey(cur, dir));
      if (!to) continue;

      const [dx, dy, dz] = DELTA[dir];
      const targetPos = [cx + dx, cy + dy, cz + dz];

      if (!pos.has(to)) {
        pos.set(to, targetPos);
      } else {
        const existing = pos.get(to);
        if (existing[0] !== targetPos[0] || existing[1] !== targetPos[1] || existing[2] !== targetPos[2]) {
          conflict.push({
            room: to,
            existing,
            attempted: targetPos,
            via: { from: cur, dir, to },
          });
        }
      }

      if (!seen.has(to)) {
        seen.add(to);
        q.push(to);
      }
    }
  }

  // Some rooms might not be reached if graph is weird; ensure all have coords if possible.
  // If unreachable, leave null coords.
  return { pos, conflict };
}

function main() {
  const args = parseArgs();

  const inPath = args.in;
  const outPath = args.out || "rooms_inserts.sql";
  const zoneId = Number(args.zone_id);
  const createdBy = Number(args.created_by);

  if (!inPath) throw new Error("Missing --in <file.json>");
  if (!Number.isFinite(zoneId)) throw new Error("Missing/invalid --zone_id <number>");
  if (!Number.isFinite(createdBy)) throw new Error("Missing/invalid --created_by <number>");

  const noCoords = !!args.no_coords;

  const startX = args.start_x !== undefined ? Number(args.start_x) : 0;
  const startY = args.start_y !== undefined ? Number(args.start_y) : 0;
  const startZ = args.start_z !== undefined ? Number(args.start_z) : 0;

  const data = JSON.parse(fs.readFileSync(inPath, "utf8"));
  validateInput(data);

  const rooms = data.rooms;
  const links = data.links;

  // Stable ordering by id (R001..)
  const roomIds = rooms.map(r => r.id).sort((a, b) => a.localeCompare(b));
  const roomById = new Map(rooms.map(r => [r.id, r]));

  const expandedLinks = buildExpandedLinks(links);
  const { exitsString, toByFromDir } = buildExitsByRoom(roomIds, expandedLinks);

  let pos = new Map();
  let conflicts = [];
  if (!noCoords) {
    const res = assignCoordinates(roomIds, toByFromDir, startX, startY, startZ);
    pos = res.pos;
    conflicts = res.conflict;
  }

  // Map room ids (R###) -> DB ids by insertion order
  // You can change this if you want to insert without specifying `id` and look up later.
  const dbIdByRoomId = new Map();
  for (let i = 0; i < roomIds.length; i++) {
    // Let MySQL auto-increment instead of forcing ids:
    // We'll not set `id` column at all; we only insert other fields.
    dbIdByRoomId.set(roomIds[i], i + 1); // internal only, not used in SQL here
  }

  const now = "NOW()";

  const lines = [];
  lines.push("-- Generated room inserts");
  lines.push(`-- zone_id=${zoneId}, created_by=${createdBy}`);
  if (!noCoords) lines.push(`-- start_xyz=${startX}:${startY}:${startZ}`);
  if (conflicts.length) {
    lines.push("-- WARNING: Coordinate conflicts detected; coordinates still generated with first-wins strategy.");
    for (const c of conflicts.slice(0, 20)) {
      lines.push(`-- conflict room=${c.room} existing=${c.existing.join(":")} attempted=${c.attempted.join(":")} via=${c.via.from} ${c.via.dir} ${c.via.to}`);
    }
    if (conflicts.length > 20) lines.push(`-- ... ${conflicts.length - 20} more conflicts`);
  }

  for (const rid of roomIds) {
    const r = roomById.get(rid);
    const exits = exitsString[rid] || "";

    const p = pos.get(rid);
    const x = noCoords || !p ? null : p[0];
    const y = noCoords || !p ? null : p[1];
    const z = noCoords || !p ? null : p[2];
    const xyzHash = (x === null || y === null || z === null) ? null : `${x},${y},${z}`;

    // Ensure inside/outside sanity
    let inside = r.inside ?? 0;
    let outside = r.outside ?? 0;
    if (inside && outside) {
      // prefer inside if both set
      outside = 0;
    }
    if (!inside && !outside) {
      // default outside
      outside = 1;
    }

    const terrainTypeId = (r.terrain_type_id === undefined ? null : r.terrain_type_id);
    const roomTypeId = (r.room_type_id === undefined ? null : r.room_type_id);

    // Column list intentionally omits `id` so AUTO_INCREMENT can work
    const sql = `
INSERT INTO rooms
(zone_id, exits, x, y, z, xyz_hash, name, description, verbose_description, inside, outside, terrain_type_id, created_at, updated_at, created_by, credits_on_ground, room_type_id)
VALUES
(${sqlEscape(zoneId)}, ${sqlEscape(exits)}, ${sqlEscape(x)}, ${sqlEscape(y)}, ${sqlEscape(z)}, ${sqlEscape(xyzHash)},
 ${sqlEscape(r.name)}, ${sqlEscape(r.description)}, ${sqlEscape(r.verbose_description)},
 ${sqlEscape(inside)}, ${sqlEscape(outside)}, ${sqlEscape(terrainTypeId)},
 ${now}, ${now}, ${sqlEscape(createdBy)}, 0, ${sqlEscape(roomTypeId)});
`.trim();

    lines.push(sql);
  }

  fs.writeFileSync(outPath, lines.join("\n") + "\n", "utf8");
  console.log(`Wrote ${outPath} with ${roomIds.length} INSERT statements.`);
  if (conflicts.length) {
    console.log(`Coordinate conflicts detected: ${conflicts.length}. See SQL comments at top of file.`);
  }
}

main();
