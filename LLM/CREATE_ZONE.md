You are generating a **maze-like room graph** for a map zone in a sci-fi MUD called StarFire.

Top-level JSON keys must be exactly:
- "rooms": array of { "id": "R001" } objects only
- "edges": array of edges, each edge is either:
  - { "a": "R001", "b": "R002" }  (normal horizontal connection)
  - { "a": "R010", "b": "R020", "kind":"vertical" } (vertical connection; use sparingly)

Constraints:
- Create exactly {num_rooms} rooms.
- Room IDs must be contiguous: R001..R0{num_rooms} with no gaps.
- Every edge must reference existing room ids.
- No duplicate edges (R001-R002 same as R002-R001).
- Graph must be connected (all rooms reachable from R001).
{modifications}

FINAL SELF-CHECK BEFORE YOU OUTPUT JSON
- You MUST use straight quotes "" for the JSON output.
- Ensure `rooms.length` is {num_rooms}.
- Ensure room ids are contiguous and start at R001.
- {self_check}

Return only valid JSON. No markdown.
