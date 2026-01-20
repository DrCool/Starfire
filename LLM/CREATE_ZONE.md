You are generating a **maze-like room graph** for a map zone in a sci-fi MUD called StarFire.

Top-level JSON keys must be exactly:
- "rooms": array of { "id": "R001" } objects only
- "edges": array of edges, each edge is either:
  - { "a": "R001", "b": "R002" }  (normal horizontal connection)
  - { "a": "R010", "b": "R020", "kind":"vertical" } (vertical connection; use sparingly)

Constraints:
- Create exactly 30 rooms.
- Room IDs must be contiguous: R001..R030 with no gaps.
- Every edge must reference existing room ids.
- No duplicate edges (R001-R002 same as R002-R001).
- Graph must be connected (all rooms reachable from R001).
- Maze-like: corridors + branches + at least 2 loops (cycle length >= 4).
- Include at least 6 dead ends (rooms with degree 1).
- Include at least 4 junctions (rooms with degree >= 3).
- Include 0 to 3 vertical edges total. If you include any, label them with "kind: 'vertical'".
- Create two backbone corridors of length 6–9 each.
- Connect them with 2–4 bridges (edges between the backbones).
- Attach 6–10 spur rooms total.
- Include 2 loops not counting the bridges.

FINAL SELF-CHECK BEFORE YOU OUTPUT JSON
- You MUST use straight quotes "" for the JSON output.
- Ensure `rooms.length` is 30.
- Ensure room ids are contiguous and start at R001.
- Ensure there are at least 6 dead ends, at least 4 junctions, at least one 4+ loop, and 0–2 vertical connections.

Return only valid JSON. No markdown.

IMPORTANT: Do not use curly quotes! Only use straight quotes "" used in programming, so the JSON can be parsed.
