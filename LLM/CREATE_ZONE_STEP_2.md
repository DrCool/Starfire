You will be given a Ruby object with an array of `rooms` which contains some basic data for indoor/outdoor roooms for an online MUD game called StarFire. You will need to create some interesting descriptions for each room to make it interesting and visual for the player.

OUTPUT RULES
- Output JSON only. No markdown. No commentary.
- The output JSON must have exactly one top-level key: `rooms`.
- Each room object must contain exactly these fields (no extras):
  - `id` (number from 1 to X)
  - `name` (string, 2–6 words)
  - `description` (string, <= 255 chars)
  - `verbose_description` (string, can be longer; do not use paragraphs)
  - `inside` (0 or 1)
  - `outside` (0 or 1)
  - `terrain_type_id` (always null)
  - `room_type_id` (integer or null)

SPECIAL ROOMS (exactly 7)
Assign exactly 7 rooms as special functional locations by setting `room_type_id` appropriately.
Use these 7 special room types (each exactly once):
1) Ship Landing / Docking Terminal (players enter the zone here)
2) Shop
3) Bank
4) Medbay
5) Training Hall
6) Bar
7) Quest Board

Below is a mapping for room_type_id values. Use only these ID numbers.

`room_types` mapping:
```
[
  { "id": 1, "name": "shop" },
  { "id": 2, "name": "bank" },
  { "id": 3, "name": "medbay  },
  { "id": 5, "name": "quest board" },
  { "id": 6, "name": "ship landing terminal" },
  { "id": 7, "name": "bar" },
  { "id": 8, "name": "training hall" }
]
```

PLACEMENT GUIDELINES (use the graph shape)
- Put Ship Landing/Docking Terminal on a room that feels like a “front door” (near the edge, not deep in loops).
- Put Medbay reachable but not the very first room (usually 2–5 moves in), preferably near a junction.
- Put Bank and Shop on or near the “main flow” (higher-traffic junctions).
- Put Bar tucked slightly off the main path (a branch or dead end), not completely central.
- Put Training Hall reachable but not right at the entrance (mid-depth).
- Put Transport Gate at the far end or behind a loop “landmark” so it feels like progression.
- The remaining non-special rooms should still be interesting traversal spaces: alleys, corridors, overlooks, maintenance shafts, holo-billboards, security checkpoints, service doors, etc.

INSIDE / OUTSIDE
- Each room must be either inside or outside, not both:
    - If `inside` = 1 then `outside` = 0
    - If `outside` = 1 then `inside` = 0
- If unsure, default most corridors/streets to outside, most facilities (bank, shop, medbay, bar, training) to inside.

TONE / COHESION
- The zone should feel like one coherent place with a clear theme.
- Use consistent sensory motifs to describe the various rooms of the zone.
- Keep `description` to one sentence; put richer detail in `verbose_description`.

A) ZONE DESCRIPTION
```
Brightash is the downtown core of Ashdown, a neon-drenched city that never sees daylight. It is always night here (similar look as Bladerunner). Rain falls constantly from condensation vents and atmospheric runoff, turning streets into mirrors for holographic advertisements. Towering high-rises press in on narrow avenues, their lower floors wrapped in shops, bars, banks, clinics, and guarded lobbies while upper levels remain locked behind security and clearance.

The city feels alive but strained — beautiful in motion, grimy up close. Music, generator hum, transit rails, and crowd noise blend into a constant low roar. Holographic ads float, dance, and glitch between buildings. Steam vents hiss from grates. The air smells of ozone, hot circuitry, street food, and recycled water.

At the very heart of downtown, there are tall high-rises housing corporate offices, secure facilities, and exclusive residences. These buildings loom over the streets, their upper levels inaccessible without special clearance. Brightash’s lower levels are a maze of public spaces, guarded entrances, and service corridors.

The high-rises are described with holo-ads flickering on their facades, security drones patrolling the airspace, and visible conduits running along their exteriors. Street level is a tangle of neon signs, market stalls, and crowded walkways (think Bladerunner). Alleyways branch off into shadowed nooks where illicit activities thrive. The lobby of several buildings can be entered, but elevators and upper floors are locked down.

Important room types commonly found in Brightash include:
  • A landing terminal
  • A bank with heavy security
  • A night clinic / medbay
  • A bar tucked into a side alley
  • High-rise lobbies with locked elevators and visible security
  • A quest board near the central crossway
  • A training loft above street level

Verticality matters: skybridges, raised walkways, stairwells, and hidden crawlspaces create shortcuts, secrets, and layered movement without confusing the map. Brightash is dense but legible — a place players learn by walking it.
```

B) ROOMS
```
```

The JSON output should be the enriched graph with all rooms fully detailed as per the instructions above, similar to this:
```
{
  "rooms":[
    {"id":1,"name":"...","description":"...","verbose_description":"...","inside":1,"outside":0,"terrain_type_id":null,"room_type_id": ...},
    ...
  ]
}
```

The `id` should be an incrementing number from 1 to X.

Now produce the enriched JSON.