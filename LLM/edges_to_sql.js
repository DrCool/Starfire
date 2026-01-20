// edges_to_sql.js
// Input JSON: { rooms:[{id,...optional fields...}], edges:[{a,b,kind?}] }
// - Embeds to grid, assigns directions, computes exits (nsweud), emits rooms INSERTs.
// - No more coordinate conflicts from LLM direction mistakes, because LLM doesn't provide dirs.

// node edges_to_sql.js --in zone.json --zone_id 3 --created_by 1 --start_x 600 --start_y 600 --start_z 10 --out rooms.sql

const fs = require("fs");

const ORDER = ["n", "s", "w", "e", "u", "d"];
const OPP = { n: "s", s: "n", w: "e", e: "w", u: "d", d: "u" };
const DELTA = {
  n: [0, -1, 0],
  s: [0, 1, 0],
  w: [-1, 0, 0],
  e: [1, 0, 0],
  u: [0, 0, -1],
  d: [0, 0, 1],
};
const NEIGHBORS_2D = [
  ["n", 0, -1],
  ["s", 0, 1],
  ["w", -1, 0],
  ["e", 1, 0],
];

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
    } else out[key] = true;
  }
  return out;
}

function sqlEscape(val) {
  if (val === null || val === undefined) return "NULL";
  if (typeof val === "number") return Number.isFinite(val) ? String(val) : "NULL";
  const s = String(val)
    .replace(/\\/g, "\\\\")
    .replace(/\u0000/g, "\\0")
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t")
    .replace(/'/g, "''");
  return `'${s}'`;
}

function edgeKey(a, b, kind = "") {
  return [a, b].sort().join("|") + "|" + kind;
}

function validate(data) {
  if (!data || typeof data !== "object") throw new Error("Input must be a JSON object.");
  if (!Array.isArray(data.rooms) || !Array.isArray(data.edges)) throw new Error("Must have rooms[] and edges[].");

  const ids = data.rooms.map(r => r.id);
  const set = new Set(ids);

  for (const id of ids) {
    if (!/^R\d{3}$/.test(id)) throw new Error(`Bad room id: ${id}`);
  }

  // Contiguous check (optional but helpful)
  const sorted = [...ids].sort();
  for (let i = 0; i < sorted.length; i++) {
    const expect = `R${String(i + 1).padStart(3, "0")}`;
    if (sorted[i] !== expect) throw new Error(`Room ids must be contiguous from R001. Expected ${expect}, got ${sorted[i]}`);
  }

  const seenEdges = new Set();
  for (const e of data.edges) {
    if (!e.a || !e.b) throw new Error(`Edge missing a/b: ${JSON.stringify(e)}`);
    if (!set.has(e.a) || !set.has(e.b)) throw new Error(`Edge references missing room: ${JSON.stringify(e)}`);
    if (e.a === e.b) throw new Error(`Self-edge not allowed: ${JSON.stringify(e)}`);
    const k = edgeKey(e.a, e.b, e.kind || "");
    if (seenEdges.has(k)) throw new Error(`Duplicate edge: ${k}`);
    seenEdges.add(k);
  }

  // Connectedness (treat edges undirected)
  const adj = {};
  for (const id of ids) adj[id] = [];
  for (const e of data.edges) {
    adj[e.a].push({ to: e.b, kind: e.kind || "" });
    adj[e.b].push({ to: e.a, kind: e.kind || "" });
  }
  const start = "R001";
  const q = [start];
  const vis = new Set();
  while (q.length) {
    const cur = q.shift();
    if (vis.has(cur)) continue;
    vis.add(cur);
    for (const n of adj[cur]) if (!vis.has(n.to)) q.push(n.to);
  }
  if (vis.size !== ids.length) {
    const missing = ids.filter(x => !vis.has(x));
    throw new Error(`Graph not connected from R001. Unreachable: ${missing.join(", ")}`);
  }

  return { ids: sorted, adj };
}


// Helper: Backtracking embedder for full adjacency constraints.
function buildUndirectedAdjFromEdges(ids, edges) {
  const adj = new Map();
  for (const id of ids) adj.set(id, []);
  for (const e of edges) {
    const kind = e.kind || "";
    adj.get(e.a).push({ to: e.b, kind });
    adj.get(e.b).push({ to: e.a, kind });
  }
  return adj;
}

function embedBacktracking(ids, edges, startX, startY, startZ) {
  // Place rooms onto an integer grid so that EVERY edge connects adjacent cells.
  // Horizontal edges require Manhattan adjacency on (x,y) at same z.
  // Vertical edges require same (x,y) and |dz|=1.

  const adj = buildUndirectedAdjFromEdges(ids, edges);

  const posById = new Map();
  const idByPos = new Map();

  function pkey(x, y, z) { return `${x}:${y}:${z}`; }
  function isFree(x, y, z) { return !idByPos.has(pkey(x, y, z)); }

  function setPos(id, x, y, z) {
    posById.set(id, [x, y, z]);
    idByPos.set(pkey(x, y, z), id);
  }

  function unsetPos(id) {
    const p = posById.get(id);
    if (p) idByPos.delete(pkey(p[0], p[1], p[2]));
    posById.delete(id);
  }

  function manhattan1(a, b) {
    return Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) === 1 && a[2] === b[2];
  }

  function vertical1(a, b) {
    return a[0] === b[0] && a[1] === b[1] && Math.abs(a[2] - b[2]) === 1;
  }

  // Candidate positions for placing `id` given it must be adjacent to an already-placed neighbor.
  function candidatesAround(neiId, kind) {
    const p = posById.get(neiId);
    if (!p) return [];
    const [x, y, z] = p;

    if (kind === "vertical") {
      return [
        [x, y, z + 1],
        [x, y, z - 1],
      ];
    }

    // Prefer east/west first to encourage boulevard-like layouts
    return [
      [x + 1, y, z],
      [x - 1, y, z],
      [x, y + 1, z],
      [x, y - 1, z],
    ];
  }

  // Order rooms: start at R001, then highest-degree first to reduce backtracking.
  const degree = new Map();
  for (const id of ids) degree.set(id, (adj.get(id) || []).length);

  // We always seed R001 first.
  const seededId = ids[0];
  setPos(seededId, startX, startY, startZ);

  // For quick constraint checks: when placing id at candidate pos, all already-placed neighbors must satisfy adjacency.
  function satisfiesNeighbors(id, candidate) {
    const neigh = adj.get(id) || [];
    for (const n of neigh) {
      if (!posById.has(n.to)) continue;
      const np = posById.get(n.to);
      if (n.kind === "vertical") {
        if (!vertical1(candidate, np)) return false;
      } else {
        if (!manhattan1(candidate, np)) return false;
      }
    }
    return true;
  }

  function placedNeighbors(id) {
    const neigh = adj.get(id) || [];
    const placed = neigh.filter(n => posById.has(n.to));
    placed.sort((a, b) => (degree.get(b.to) - degree.get(a.to)) || a.to.localeCompare(b.to));
    return placed;
  }

  function scoreCandidate(id, candidate) {
    // Count how many already-placed neighbors this candidate satisfies
    let score = 0;
    const neigh = adj.get(id) || [];
    for (const n of neigh) {
      if (!posById.has(n.to)) continue;
      const np = posById.get(n.to);
      if (n.kind === "vertical") {
        if (vertical1(candidate, np)) score++;
      } else {
        if (manhattan1(candidate, np)) score++;
      }
    }
    return score;
  }

  function candidatesForId(id) {
    const placed = placedNeighbors(id);
    if (!placed.length) return [];

    const seen = new Set();
    const out = [];

    // Generate candidates around ALL placed neighbors (not just one anchor)
    for (const pn of placed) {
      for (const c of candidatesAround(pn.to, pn.kind)) {
        const [cx, cy, cz] = c;
        const pk = pkey(cx, cy, cz);
        if (seen.has(pk)) continue;
        seen.add(pk);
        out.push(c);
      }
    }

    // Prefer candidates that satisfy more already-placed neighbors first
    out.sort((c1, c2) => scoreCandidate(id, c2) - scoreCandidate(id, c1));

    return out;
  }

  // We always seed R001 first.
  // (already seeded seededId above)

  function allPlaced() {
    return posById.size === ids.length;
  }

  function nextUnplacedId() {
    // Choose the next room to place using a "most constrained" heuristic:
    // - must have at least one placed neighbor (graph is connected)
    // - prefer more placed neighbors
    // - prefer fewer viable candidate positions (MRV)

    let bestId = null;
    let bestPlacedNeighborCount = -1;
    let bestCandCount = Infinity;

    for (const id of ids) {
      if (posById.has(id)) continue;
      const placed = placedNeighbors(id);
      if (!placed.length) continue;

      // Count viable candidates (free + satisfy all already-placed neighbor constraints)
      const cand = candidatesForId(id).filter(c => {
        const [cx, cy, cz] = c;
        return isFree(cx, cy, cz) && satisfiesNeighbors(id, c);
      });

      const pn = placed.length;
      const cc = cand.length;

      if (pn > bestPlacedNeighborCount || (pn === bestPlacedNeighborCount && cc < bestCandCount)) {
        bestId = id;
        bestPlacedNeighborCount = pn;
        bestCandCount = cc;
        // Hard prune: if cc === 0 we still keep it as best to fail fast on this branch.
      }
    }

    return bestId;
  }

  function backtrackDynamic() {
    if (allPlaced()) return true;

    const id = nextUnplacedId();
    if (!id) return false;

    const cand = candidatesForId(id);
    for (const c of cand) {
      const [cx, cy, cz] = c;
      if (!isFree(cx, cy, cz)) continue;
      if (!satisfiesNeighbors(id, c)) continue;

      setPos(id, cx, cy, cz);
      if (backtrackDynamic()) return true;
      unsetPos(id);
    }

    return false;
  }

  const ok = backtrackDynamic();
  if (!ok) {
    throw new Error(
      "Embedding failed: could not place all rooms to satisfy all edges. " +
      "This graph may not be grid-embeddable in 2D without additional vertical edges."
    );
  }

  return { posById, idByPos };
}

// Simple embedding strategy:
// - Place R001 at start xyz.
// - BFS outward.
// - For each node, place unplaced neighbors into open adjacent grid cells.
// - Prefer continuing corridors by placing neighbors in same direction as parent->node when possible.
// - Uses light backtracking if stuck.
function embed(ids, adj, startX, startY, startZ) {
  const posById = new Map();      // id -> [x,y,z]
  const idByPos = new Map();      // "x:y:z" -> id
  const parentDir = new Map();    // child -> dir from parent (for corridor bias)

  function pkey(x, y, z) { return `${x}:${y}:${z}`; }
  function isFree(x, y, z) { return !idByPos.has(pkey(x, y, z)); }

  function place(id, x, y, z) {
    posById.set(id, [x, y, z]);
    idByPos.set(pkey(x, y, z), id);
  }

  place("R001", startX, startY, startZ);

  const queue = ["R001"];
  const visited = new Set();

  while (queue.length) {
    const cur = queue.shift();
    if (visited.has(cur)) continue;
    visited.add(cur);

    if (!posById.has(cur)) {
      // eslint-disable-next-line no-console
      console.log("Skipping unplaced:", cur);
    }
    const curPos = posById.get(cur);
    if (!curPos) continue; // not placed yet; will be handled later
    const neighbors = adj[cur] || [];

    // Partition neighbors: vertical first (rare), then horizontal
    const vN = neighbors.filter(n => (n.kind || "") === "vertical");
    const hN = neighbors.filter(n => (n.kind || "") !== "vertical");

    // Enqueue all neighbors (so we eventually expand them)
    for (const n of neighbors) if (!visited.has(n.to)) queue.push(n.to);

    // Place vertical neighbors (z+1 then z-1 preference)
    for (const n of vN) {
      if (posById.has(n.to)) continue;
      const [cx, cy, cz] = curPos;
      const candidates = [
        [cx, cy, cz + 1],
        [cx, cy, cz - 1],
      ];
      const spot = candidates.find(([x, y, z]) => isFree(x, y, z));
      if (!spot) continue; // if blocked, we'll try later when expanded from other side
      place(n.to, spot[0], spot[1], spot[2]);
      parentDir.set(n.to, spot[2] > cz ? "u" : "d");
    }

    // Place horizontal neighbors around cur
    // Corridor bias: if cur has a parentDir, try continuing forward first.
    const bias = parentDir.get(cur); // dir used to reach cur from parent
    const preferredOrder = bias === "n" ? ["n", "e", "w", "s"]
      : bias === "s" ? ["s", "e", "w", "n"]
        : bias === "e" ? ["e", "n", "s", "w"]
          : bias === "w" ? ["w", "n", "s", "e"]
            : ["n", "s", "w", "e"];

    const dirToDelta2D = { n:[0,-1], s:[0,1], w:[-1,0], e:[1,0] };

    for (const n of hN) {
      if (posById.has(n.to)) continue;

      const [cx, cy, cz] = curPos;

      // Try to place in a free adjacent cell, using preferred order
      let placed = false;
      for (const d of preferredOrder) {
        const [dx, dy] = dirToDelta2D[d];
        const tx = cx + dx, ty = cy + dy, tz = cz;
        if (isFree(tx, ty, tz)) {
          place(n.to, tx, ty, tz);
          parentDir.set(n.to, d);
          queue.push(n.to);
          placed = true;
          break;
        }
      }

      // If no adjacent spot free, leave unplaced; may be placed when expanded from another neighbor.
      if (!placed) continue;
    }
  }

  // If any remain unplaced, do a second pass: try to place them near ANY placed neighbor.
  for (const id of ids) {
    if (posById.has(id)) continue;

    // Find a placed neighbor
    const placedNeighbor = (adj[id] || []).find(n => posById.has(n.to));
    if (!placedNeighbor) continue; // should not happen if connected

    const [nx, ny, nz] = posById.get(placedNeighbor.to);
    // Try 2D ring around neighbor to find a free spot
    let found = null;
    for (const [d, dx, dy] of NEIGHBORS_2D) {
      const tx = nx + dx, ty = ny + dy, tz = nz;
      if (isFree(tx, ty, tz)) { found = [tx, ty, tz]; break; }
    }
    if (!found) {
      // expand search radius 2
      outer: for (let rx = -2; rx <= 2; rx++) {
        for (let ry = -2; ry <= 2; ry++) {
          if (Math.abs(rx) + Math.abs(ry) !== 2) continue;
          const tx = nx + rx, ty = ny + ry, tz = nz;
          if (isFree(tx, ty, tz)) { found = [tx, ty, tz]; break outer; }
        }
      }
    }
    if (found) place(id, found[0], found[1], found[2]);
  }

  // Final sanity: all placed?
  const unplaced = ids.filter(id => !posById.has(id));
  if (unplaced.length) {
    throw new Error(`Embedding failed; unplaced rooms: ${unplaced.join(", ")}`);
  }

  return { posById, idByPos };
}

function assignDirectionsWithoutCoords(ids, edges) {
  // Assign reciprocal n/s/e/w (and u/d for vertical) directions to undirected edges
  // WITHOUT relying on coordinates.
  // Uses backtracking to avoid duplicate directions per room.

  const H_DIRS = ["e", "w", "n", "s"]; // prefer e/w to form a main corridor

  const used = new Map(); // roomId -> Set(dir)
  for (const id of ids) used.set(id, new Set());

  function useDir(roomId, dir) {
    used.get(roomId).add(dir);
  }

  function unuseDir(roomId, dir) {
    used.get(roomId).delete(dir);
  }

  function hasDir(roomId, dir) {
    return used.get(roomId).has(dir);
  }

  const vertical = [];
  const horizontal = [];
  for (const e of edges) {
    if ((e.kind || "") === "vertical") vertical.push(e);
    else horizontal.push(e);
  }

  // Pre-assign vertical edges with u/d if possible
  const chosen = new Map(); // key "a|b|kind" with sorted a,b -> { aToB, bToA }

  function ekey(a, b, kind) {
    const s = [a, b].sort();
    return `${s[0]}|${s[1]}|${kind || ""}`;
  }

  for (const e of vertical) {
    const k = ekey(e.a, e.b, e.kind || "vertical");
    // Try a->b as u if available, else d; and ensure reciprocal available.
    const tries = ["u", "d"];
    let placed = false;
    for (const d of tries) {
      const od = OPP[d];
      if (!hasDir(e.a, d) && !hasDir(e.b, od)) {
        useDir(e.a, d);
        useDir(e.b, od);
        chosen.set(k, { a: e.a, b: e.b, aToB: d, bToA: od });
        placed = true;
        break;
      }
    }
    if (!placed) {
      throw new Error(`Could not assign vertical directions for ${e.a}-${e.b}; room already used u/d.`);
    }
  }

  // Sort horizontal edges: handle “spine-ish” edges first (consecutive ids)
  function num(id) { return Number(id.slice(1)); }
  horizontal.sort((e1, e2) => {
    const d1 = Math.abs(num(e1.a) - num(e1.b));
    const d2 = Math.abs(num(e2.a) - num(e2.b));
    return d1 - d2;
  });

  // Backtracking over horizontal edges
  function backtrack(i) {
    if (i >= horizontal.length) return true;

    const e = horizontal[i];
    const k = ekey(e.a, e.b, "");

    // Try dirs in preferred order; require reciprocal free.
    for (const d of H_DIRS) {
      const od = OPP[d];
      if (hasDir(e.a, d) || hasDir(e.b, od)) continue;

      useDir(e.a, d);
      useDir(e.b, od);
      chosen.set(k, { a: e.a, b: e.b, aToB: d, bToA: od });

      if (backtrack(i + 1)) return true;

      // undo
      chosen.delete(k);
      unuseDir(e.a, d);
      unuseDir(e.b, od);
    }

    return false;
  }

  const ok = backtrack(0);
  if (!ok) {
    throw new Error(
      "Failed to assign directions without coordinates. The graph likely has a node degree > 4 (horizontal) " +
      "or too many constraints to fit into n/s/e/w."
    );
  }

  // Emit directed links for ALL edges using the chosen directions
  const links = [];

  for (const e of edges) {
    const kind = (e.kind || "");
    const k = ekey(e.a, e.b, kind ? kind : "");
    const picked = chosen.get(k) || chosen.get(ekey(e.a, e.b, kind || ""));
    if (!picked) {
      // This should not happen
      throw new Error(`Missing direction assignment for edge ${e.a}-${e.b} (${kind || "horizontal"})`);
    }

    // picked stores original a,b and their directions
    links.push({ from: picked.a, dir: picked.aToB, to: picked.b });
    links.push({ from: picked.b, dir: picked.bToA, to: picked.a });
  }

  return links;
}

function buildDirLinksFromEmbedding(ids, edges, posById, idByPos) {
  // For each undirected edge, infer direction from coordinate delta
  // Produces directed links (both directions) with consistent n/s/e/w/u/d.
  const links = [];
  const seenFromDir = new Set(); // to avoid two exits same dir from same room

  function pkey(x, y, z) { return `${x}:${y}:${z}`; }

  function tryRelocate(toId, fromId, preferDir) {
    const fromPos = posById.get(fromId);
    const toPos = posById.get(toId);
    if (!fromPos || !toPos) return false;

    const [fx, fy, fz] = fromPos;
    const [tx, ty, tz] = toPos;

    const candidates = [];

    if (preferDir === "u" || preferDir === "d") {
      candidates.push([fx, fy, fz + 1]);
      candidates.push([fx, fy, fz - 1]);
    } else {
      candidates.push([fx + 1, fy, fz]); // e
      candidates.push([fx - 1, fy, fz]); // w
      candidates.push([fx, fy + 1, fz]); // n
      candidates.push([fx, fy - 1, fz]); // s
    }

    for (const [nx, ny, nz] of candidates) {
      const pk = pkey(nx, ny, nz);
      if (!idByPos.has(pk)) {
        // Free spot: move `toId`
        idByPos.delete(pkey(tx, ty, tz));
        idByPos.set(pk, toId);
        posById.set(toId, [nx, ny, nz]);
        return true;
      }
    }

    return false;
  }

  function addLink(from, dir, to) {
    const k = `${from}:${dir}`;
    if (seenFromDir.has(k)) {
      // Attempt to relocate `to` around `from` to get a different direction.
      // This is safe only if `to` hasn't had other edges processed yet.
      const moved = tryRelocate(to, from, dir);
      if (!moved) {
        throw new Error(
          `Embedding duplicate direction ${dir} from ${from} to ${to}. ` +
          `No free adjacent slot to relocate; graph too dense for current embedder.`
        );
      }

      // After relocation, recompute the direction and retry
      const [ax, ay, az] = posById.get(from);
      const [bx, by, bz] = posById.get(to);
      const dx = bx - ax, dy = by - ay, dz = bz - az;

      let newDir = null;
      if (Math.abs(dz) === 1 && dx === 0 && dy === 0) newDir = dz === 1 ? "u" : "d";
      else if (dz === 0 && Math.abs(dx) + Math.abs(dy) === 1) {
        if (dx === 1) newDir = "e";
        else if (dx === -1) newDir = "w";
        else if (dy === 1) newDir = "n";
        else if (dy === -1) newDir = "s";
      }

      if (!newDir) {
        throw new Error(`Relocation broke adjacency for edge ${from} -> ${to}.`);
      }

      const nk = `${from}:${newDir}`;
      if (seenFromDir.has(nk)) {
        throw new Error(`Relocation still collides: ${from} already has ${newDir}.`);
      }
      seenFromDir.add(nk);
      links.push({ from, dir: newDir, to });
      return;
    }

    seenFromDir.add(k);
    links.push({ from, dir, to });
  }

  for (const e of edges) {
    const kind = e.kind || "";
    const [ax, ay, az] = posById.get(e.a);
    const [bx, by, bz] = posById.get(e.b);
    const dx = bx - ax, dy = by - ay, dz = bz - az;

    let dirAB = null;

    if (kind === "vertical") {
      if (dx !== 0 || dy !== 0 || Math.abs(dz) !== 1) {
        // we expect vertical edges to be stacked; if not, still force u/d based on dz sign
        dirAB = dz >= 0 ? "u" : "d";
      } else dirAB = dz === -1 ? "u" : "d";
    } else {
      // horizontal edge should be manhattan-adjacent
      if (dz !== 0) throw new Error(`Non-vertical edge spans z for ${e.a}-${e.b}.`);
      // if (Math.abs(dx) + Math.abs(dy) !== 1) {
      //   throw new Error(`Non-vertical edge not adjacent in embedding for ${e.a}-${e.b}.`);
      // }
      if (dx === 1) dirAB = "e";
      else if (dx === -1) dirAB = "w";
      else if (dy === 1) dirAB = "n";
      else if (dy === -1) dirAB = "s";
    }

    const dirBA = OPP[dirAB];
    addLink(e.a, dirAB, e.b);
    addLink(e.b, dirBA, e.a);
  }

  return links;
}

function assignCoordsFromDirectedLinks(ids, directedLinks, startX, startY, startZ) {
  // Derive x/y/z from assigned directions. This can still conflict on cycles;
  // we keep first-wins and report conflicts.
  const posById = new Map(); // id -> [x,y,z]
  const conflicts = [];

  const adj = new Map(); // from -> array of {dir,to}
  for (const id of ids) adj.set(id, []);
  for (const l of directedLinks) {
    if (!adj.has(l.from)) adj.set(l.from, []);
    adj.get(l.from).push({ dir: l.dir, to: l.to });
  }

  const start = ids[0];
  posById.set(start, [startX, startY, startZ]);

  const q = [start];
  const seen = new Set([start]);

  while (q.length) {
    const cur = q.shift();
    const curPos = posById.get(cur);
    if (!curPos) continue;
    const [cx, cy, cz] = curPos;

    const nbrs = adj.get(cur) || [];
    for (const { dir, to } of nbrs) {
      const delta = DELTA[dir];
      if (!delta) continue;
      const [dx, dy, dz] = delta;
      const target = [cx + dx, cy + dy, cz + dz];

      if (!posById.has(to)) {
        posById.set(to, target);
      } else {
        const existing = posById.get(to);
        if (existing[0] !== target[0] || existing[1] !== target[1] || existing[2] !== target[2]) {
          conflicts.push({ room: to, existing, attempted: target, via: { from: cur, dir, to } });
        }
      }

      if (!seen.has(to)) {
        seen.add(to);
        q.push(to);
      }
    }
  }

  return { posById, conflicts };
}

function exitsByRoom(ids, directedLinks) {
  const exits = {};
  for (const id of ids) exits[id] = new Set();
  for (const l of directedLinks) exits[l.from].add(l.dir);
  const out = {};
  for (const id of ids) out[id] = ORDER.filter(d => exits[id].has(d)).join("");
  return out;
}

function main() {
  const args = parseArgs();
  const inPath = args.in;
  const outPath = args.out || "rooms.sql";
  const zoneId = Number(args.zone_id);
  const createdBy = Number(args.created_by);
  const startX = args.start_x !== undefined ? Number(args.start_x) : 0;
  const startY = args.start_y !== undefined ? Number(args.start_y) : 0;
  const startZ = args.start_z !== undefined ? Number(args.start_z) : 0;

  if (!inPath) throw new Error("Missing --in <file.json>");
  if (!Number.isFinite(zoneId)) throw new Error("Missing/invalid --zone_id");
  if (!Number.isFinite(createdBy)) throw new Error("Missing/invalid --created_by");

  const data = JSON.parse(fs.readFileSync(inPath, "utf8"));
  const { ids, adj } = validate(data);

  // Embed the entire graph onto the grid so EVERY edge is a real adjacent move.
  const { posById } = embedBacktracking(ids, data.edges, startX, startY, startZ);

  // Derive reciprocal directed links from coordinates (never conflicts if embedding succeeded)
  const directedLinks = [];
  for (const e of data.edges) {
    const kind = e.kind || "";
    const aPos = posById.get(e.a);
    const bPos = posById.get(e.b);
    const dx = bPos[0] - aPos[0];
    const dy = bPos[1] - aPos[1];
    const dz = bPos[2] - aPos[2];

    let dirAB = null;
    if (kind === "vertical") {
      // Convention: up means z-1, down means z+1
      if (dz === -1) dirAB = "u";
      else if (dz === 1) dirAB = "d";
    } else {
      // Convention: north means y-1, south means y+1
      if (dx === 1) dirAB = "e";
      else if (dx === -1) dirAB = "w";
      else if (dy === -1) dirAB = "n";
      else if (dy === 1) dirAB = "s";
    }

    if (!dirAB) {
      throw new Error(`Embedding produced non-adjacent edge ${e.a}-${e.b}.`);
    }

    directedLinks.push({ from: e.a, dir: dirAB, to: e.b });
    directedLinks.push({ from: e.b, dir: OPP[dirAB], to: e.a });
  }

  // Sanity: ensure every exit corresponds to an actual neighbor at from+DELTA[dir]
  const { kept: sanitizedLinks, dropped } = sanitizeDirectedLinksAgainstCoords(ids, directedLinks, posById);
  if (dropped.length) {
    console.log(`WARNING: Dropped ${dropped.length} invalid directed links (exits leading to nowhere / mismatched coords).`);
    for (const d of dropped.slice(0, 20)) {
      if (d.reason === "no_room_at_expected_coord") {
        console.log(`  drop ${d.from} ${d.dir} ${d.to} : no room at ${d.expectedToAt}`);
      } else if (d.reason === "coord_mismatch") {
        console.log(`  drop ${d.from} ${d.dir} ${d.to} : expected ${d.expectedTo} at ${d.expectedToAt}`);
      } else {
        console.log(`  drop ${d.from} ${d.dir} ${d.to} : ${d.reason}`);
      }
    }
    if (dropped.length > 20) console.log(`  ... ${dropped.length - 20} more`);
  }

  const exits = exitsByRoom(ids, sanitizedLinks);

  // Emit SQL inserts (omit id so AUTO_INCREMENT assigns)
  const now = "NOW()";
  const lines = [];
  lines.push("-- Generated by edges_to_sql.js");
  lines.push(`-- zone_id=${zoneId}, created_by=${createdBy}`);
  lines.push(`-- start_xyz=${startX}:${startY}:${startZ}`);

  // Helpful: write a debug JSON alongside (optional)
  const debug = {
    rooms: ids.map(id => {
      const p = posById.get(id);
      return {
        ...data.rooms.find(r => r.id === id),
        id,
        x: p ? p[0] : null,
        y: p ? p[1] : null,
        z: p ? p[2] : null,
        exits: exits[id],
      };
    }),
    links: sanitizedLinks,
  };
  fs.writeFileSync("derived_layout.json", JSON.stringify(debug, null, 2));

  for (const id of ids) {
    const r = data.rooms.find(rr => rr.id === id) || { id };

    const p = posById.get(id);
    const x = p ? p[0] : null;
    const y = p ? p[1] : null;
    const z = p ? p[2] : null;
    const xyzHash = (x === null || y === null || z === null) ? null : `${x},${y},${z}`;

    let inside = r.inside ?? 0;
    let outside = r.outside ?? 0;
    if (inside && outside) outside = 0;
    if (!inside && !outside) outside = 1;

    const terrainTypeId = r.terrain_type_id ?? null;
    const roomTypeId = r.room_type_id ?? null;

    const name = r.name ?? id;
    const description = r.description ?? "";
    const verbose = r.verbose_description ?? "";

    const sql = `
INSERT INTO rooms
(zone_id, exits, x, y, z, xyz_hash, name, description, verbose_description, inside, outside, terrain_type_id, created_at, updated_at, created_by, credits_on_ground, room_type_id)
VALUES
(${sqlEscape(zoneId)}, ${sqlEscape(exits[id])}, ${sqlEscape(x)}, ${sqlEscape(y)}, ${sqlEscape(z)}, ${sqlEscape(xyzHash)},
 ${sqlEscape(name)}, ${sqlEscape(description)}, ${sqlEscape(verbose)},
 ${sqlEscape(inside)}, ${sqlEscape(outside)}, ${sqlEscape(terrainTypeId)},
 ${now}, ${now}, ${sqlEscape(createdBy)}, 0, ${sqlEscape(roomTypeId)});
`.trim();
    lines.push(sql);
  }

  fs.writeFileSync(outPath, lines.join("\n") + "\n", "utf8");
  console.log(`Wrote ${outPath} (${ids.length} rooms). Also wrote derived_layout.json for debugging.`);
}

// --- Helper: Sanitize directed links against coordinates ---
function sanitizeDirectedLinksAgainstCoords(ids, directedLinks, posById) {
  // Drop any directed link whose direction does not match the actual coordinate delta,
  // or whose target room is not located at from+DELTA[dir]. This prevents exits that lead to nowhere.

  const byPos = new Map(); // "x,y,z" -> id
  for (const id of ids) {
    const p = posById.get(id);
    if (!p) continue;
    byPos.set(`${p[0]},${p[1]},${p[2]}`, id);
  }

  const kept = [];
  const dropped = [];

  for (const l of directedLinks) {
    const p = posById.get(l.from);
    if (!p) { dropped.push({ ...l, reason: "missing_from_coords" }); continue; }

    const delta = DELTA[l.dir];
    if (!delta) { dropped.push({ ...l, reason: "bad_dir" }); continue; }

    const [dx, dy, dz] = delta;
    const key = `${p[0] + dx},${p[1] + dy},${p[2] + dz}`;
    const expectedTo = byPos.get(key);

    if (!expectedTo) {
      dropped.push({ ...l, reason: "no_room_at_expected_coord", expectedToAt: key });
      continue;
    }

    if (expectedTo !== l.to) {
      dropped.push({ ...l, reason: "coord_mismatch", expectedTo, expectedToAt: key });
      continue;
    }

    kept.push(l);
  }

  return { kept, dropped };
}

main();