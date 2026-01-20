## Quest System Overview (Starfire MUD)

This document describes the **quest system database schema** and how quests are defined, progressed, and reacted to in the game world.

The quest system is designed to support:
- simple starter quests (kill, fetch, escort, repair)
- multi-step narrative quests
- late-game epic quests (e.g. *The Broken Star*)
- per-character quest progress
- NPC and room reactions via quest flags without requiring global world-state changes.

### Core Concepts

- **Quest**: a reusable definition (what the quest is)
- **Quest Step**: an ordered stage in a quest
- **Quest Objective**: a concrete requirement (kill, collect, talk, etc.)
- **Quest Rewards**: data-driven rewards granted on completion
- **Quest Prerequisites**: requirements to start a quest
- **Character Quest**: a specific character’s run of a quest
- **Objective Progress**: per-character progress tracking
- **Character Flags**: durable per-character markers used for reactions, gating, and unlocks

### Table Summary

#### `quests`
Defines a quest.

- One row per quest
- Identified by a stable `quest_key`
- Can be level-gated, repeatable, or inactive

**Key columns**
- `quest_key`: unique string identifier (used in code and flags)
- `min_level`, `max_level`: availability range
- `giver_npc_id`: NPC who offers the quest (optional)
- `start_room_id`: where the quest can start (optional)
- `metadata_json`: tags, faction info, etc.

#### `quest_steps`
Defines ordered stages within a quest.

- A quest has 1+ steps
- Steps are completed sequentially
- Steps can optionally set flags when they start or finish

**Key columns**
- `step_number`: order within the quest (1, 2, 3, …)
- `on_start_flags_json`: flags to set when step begins
- `on_complete_flags_json`: flags to set when step completes

#### `quest_objectives`
Defines what must be done to complete a step.

Each objective is **atomic** and machine-checkable.

**Supported objective types**
- `kill`
- `collect`
- `deliver`
- `talk`
- `visit`
- `escort`
- `use`

**Key columns**
- `objective_type`: type of action
- `target_type`: npc | mob | item | room | object
- `target_id`: string ID or key (NPC ID, item key, mob key, etc.)
- `target_room_id`: destination room (for escort/visit)
- `required_count`: number required
- `parameters_json`: flexible configuration (allowed mobs, delivery NPC, etc.)

#### `character_quests`
When a player accepts a quest, a new row is created in `character_quests` which tracks a player's’s participation and progress in a quest.

**Key columns**
- `character_id`: references `player_characters.id`
- `quest_id`: which quest
- `state`: active | completed | failed | abandoned
- `current_step_number`: which step the character is on
- `started_at`, `completed_at`
- `cooldown_until`: for repeatable quests

#### `character_quest_objectives`
Tracks per-character progress for each objective.

- One row per objective per character quest

**Key columns**
- `current_count`: progress counter
- `is_completed`: objective completion flag
- `progress_json`: stores granular details (e.g. which rooms visited)

#### `quest_rewards`
Defines rewards granted when a quest completes.

Rewards are data-driven and ordered.

**Supported reward types**
- `credits`
- `xp`
- `item`
- `flag`
- `npc_companion`
- `ship_unlock`

**Key columns**
- `reward_type`
- `amount`
- `item_id`
- `flag_key`, `flag_value`
- `parameters_json`

#### `quest_prerequisites`
Defines requirements before a quest can be started.

**Supported prerequisite types**
- `level`
- `quest_completed`
- `flag`

**Examples**
- Requires player character to be at least level 15, or at least level 4
- Requires another quest to be completed
- Requires a specific character flag

### Character Flags (Reactive World Layer)

#### `character_flags`
Stores persistent per-character flags.

Flags are used to:
- gate NPC dialogue
- gate room flavor text
- unlock future quests
- track major accomplishments

**Key columns**
- `flag_key`: e.g. `quest.kfo.loader_droid.fixed`
- `flag_value`: usually `'1'`
- `set_by_quest_id`: source quest (optional)
- `expires_at`: optional (for timed flags later)

### NPC / Room Reactions

NPCs and rooms can react to completed quests using flags.

#### Gating fields added to existing tables (npc_sayings and room_sayings):

The `*_sayings` tables contain text that appears randomly when the player is in the same room as the NPC or in the room itself. This creates "atmosphere" and immersion.
 
- `npc_sayings.requires_flag_key`
- `npc_sayings.requires_flag_value`
- `npc_sayings.once_per_player`
- `room_sayings.requires_flag_key`
- `room_sayings.requires_flag_value`
- `room_sayings.once_per_player`

Sayings are shown **only if the character has the required flag**.

#### `character_seen_sayings`
Tracks one-time NPC or room lines already seen by a character.

Used when `once_per_player = 1`. This ensures that the line is only shown once per character.

### Quest Progress Model (Runtime)

Game events drive quest progress:

- on kill → update `kill` objectives
- on item pickup → update `collect` objectives
- on NPC talk → update `talk` / `deliver` objectives
- on room entry → update `visit` / `escort` objectives

When all objectives in a step are complete:
- advance `current_step_number`
- apply step completion flags

When the final step completes:
- mark quest `completed`
- grant rewards
- set quest completion flags

### Design Rules

- Quests are **per-character**, not global
- Flags affect **perception and access**, not world permanence
- Steps and objectives are data-driven
- New quest types should not require schema changes
- Complex quests are built by combining multiple steps and objectives

### Example Flag Naming Convention
Flags follow a hierarchical dot-separated format:
`quest.<quest_key>.<descriptive_suffix>`

The `<descriptive_suffix>` should describe a durable outcome or unlock, not transient progress (e.g. use `.completed`, `.fixed`, `.unlocked`).

Examples:
- `quest.kfo.loader_droid.fixed`
- `quest.kfo.vermin.completed`
- `quest.ship.private_unlock`

### Quest Objective Types

The `quest_objectives` table has a `objective_type` column that defines what kind of action is required. Here are the supported types and their configurations:

The `fields` array lists the columns in the `quest_objectives` table that are relevant for that objective type. The `parameters_json` field allows for additional configuration options specific to each objective type.

```json
{
  "quest_objective_types": [
    {
      "type": "kill",
      "description": "Defeat a certain number of a specific creature type.",
      "target_type": [
        "creature"
      ],
      "fields": [
        "target_id",
        "required_count",
        "target_room_id",
        "parameters_json.allowed_room_ids"
      ],
      "parameters_json": {
        "allowed_room_ids": "number[] (optional) - restrict kills to specific rooms"
      }
    },
    {
      "type": "kill_unique",
      "description": "Kill a specific named NPC or a specific named creature instance (boss/target).",
      "target_type": [
        "npc",
        "creature_instance"
      ],
      "fields": [
        "target_id",
        "required_count"
      ],
      "parameters_json": {}
    },
    {
      "type": "turnin",
      "description": "Return to a location to complete or advance the quest (usually triggered by 'complete <quest_id>' at a board or target room).",
      "target_type": [
        "room"
      ],
      "fields": [
        "target_room_id",
        "required_count",
        "parameters_json.requires_previous_steps_complete"
      ],
      "parameters_json": {
        "requires_previous_steps_complete": "0|1 (optional) - enforce earlier steps complete before turn-in"
      }
    },
    {
      "type": "examine",
      "description": "Examine a prop/object/NPC to gather info or trigger progression.",
      "target_type": [
        "prop",
        "object",
        "npc"
      ],
      "fields": [
        "target_id",
        "target_room_id",
        "required_count",
        "parameters_json.allowed_room_ids",
        "parameters_json.match_name"
      ],
      "parameters_json": {
        "allowed_room_ids": "number[] (optional) - restrict where examining counts",
        "match_name": "string (optional) - canonical name/alias like 'console' to help matching"
      }
    },
    {
      "type": "visit",
      "description": "Enter a specific room (triggered when the player arrives).",
      "target_type": [
        "room"
      ],
      "fields": [
        "target_room_id",
        "required_count"
      ],
      "parameters_json": {
        "on_entry_spawn_object": "number (optional) - object_id to spawn when player enters room",
        "on_entry_spawn_creature": "number (optional) - creature_id to spawn when player enters room"
      }
    },
    {
      "type": "escort",
      "description": "Escort an NPC safely to a destination room.",
      "target_type": [
        "npc"
      ],
      "fields": [
        "target_id",
        "target_room_id",
        "required_count"
      ],
      "parameters_json": {
        "requires_following": "0|1 (optional) - require NPC to be following player at completion",
        "fail_if_npc_dead": "0|1 (optional) - fail objective if escort NPC dies"
      }
    },
    {
      "type": "say",
      "description": "Player says something that matches keywords or an exact phrase; optionally requires a specific NPC to be present.",
      "target_type": [
        "npc",
        "room"
      ],
      "fields": [
        "target_id (optional)",
        "target_room_id (optional)",
        "required_count",
        "parameters_json"
      ],
      "parameters_json": {
        "keywords_any": "string[] (optional) - any phrase match triggers",
        "keywords_all": "string[] (optional) - all phrase matches required",
        "exact_phrase": "string (optional) - normalized exact match",
        "requires_npc_id": "number (optional) - NPC must be present in room",
        "allowed_room_ids": "number[] (optional) - restrict where it can trigger",
        "min_words": "number (optional) - anti-accidental trigger guard",
        "dialog_hint": "string (optional) - Text that is shown if player has active quest and is in the correct room (based on target_type) but didn't say the right keywords",
        "response_text": "string (optional) - Text that is printed to the player's screen in response"
      }
    },
    {
      "type": "collect",
      "description": "Obtain one or more items (triggered when item enters inventory).",
      "target_type": [
        "object"
      ],
      "fields": [
        "target_id",
        "required_count"
      ],
      "parameters_json": {
        "allowed_sources": "string[] (optional) - e.g. ['loot','shop','quest_reward']"
      }
    },
    {
      "type": "deliver",
      "description": "Bring an item to a room or NPC and deliver it (triggered by a deliver action, or by turn-in validation).",
      "target_type": [
        "room",
        "npc"
      ],
      "fields": [
        "target_room_id (or target_id if npc)",
        "required_count",
        "parameters_json.item_object_id"
      ],
      "parameters_json": {
        "item_object_id": "number - object_id that must be delivered",
        "consume_item_on_complete": "0|1 (optional) - remove item(s) from inventory when completed"
      }
    },
    {
      "type": "use",
      "description": "Use a specific item on a target (prop/npc/room).",
      "target_type": [
        "prop",
        "npc",
        "room"
      ],
      "fields": [
        "target_id",
        "target_room_id (optional)",
        "required_count",
        "parameters_json.required_item_id"
      ],
      "parameters_json": {
        "required_item_id": "number - object_id required to use",
        "allowed_room_ids": "number[] (optional) - restrict where it can trigger",
        "consume_item_on_use": "0|1 (optional) - remove item when used"
      }
    },
    {
      "type": "activate",
      "description": "Activate a device/system (typically a prop or room device).",
      "target_type": [
        "prop",
        "room"
      ],
      "fields": [
        "target_id (optional)",
        "target_room_id",
        "required_count"
      ],
      "parameters_json": {
        "requires_item_id": "number (optional) - require item in inventory to activate",
        "allowed_room_ids": "number[] (optional)"
      }
    },
    {
      "type": "disable",
      "description": "Disable a device/system or an NPC (alarm, corrupted node, security grid, etc.).",
      "target_type": [
        "prop",
        "npc",
        "room"
      ],
      "fields": [
        "target_id (optional)",
        "target_room_id (optional)",
        "required_count"
      ],
      "parameters_json": {
        "requires_item_id": "number (optional) - require item in inventory to disable",
        "allowed_room_ids": "number[] (optional)"
      }
    },
    {
      "type": "survive",
      "description": "Remain alive for a duration (often in a specific room).",
      "target_type": [
        "room"
      ],
      "fields": [
        "target_room_id",
        "required_count",
        "parameters_json.seconds"
      ],
      "parameters_json": {
        "seconds": "number - duration that must be survived",
        "fail_on_leave_room": "0|1 (optional) - fail if player leaves room before time",
        "allowed_room_ids": "number[] (optional) - alternative room constraints"
      }
    }
  ]
}
```

Additional objective types can be added, but please indicate what you have added so I can add them to the code.

## Game Theme

The game of Starfire takes place in a galaxy powered by old stars, old machines, and old decisions—kept alive by people willing to deal with what still works.

### The Galaxy, the Continuum, and the Long War

The galaxy of Starfire is not young. It is expansive, technologically advanced, and deeply reliant on systems that were designed centuries ago. Civilization did not grow slowly and carefully—it expanded rapidly, powered by breakthroughs that allowed humanity and allied species to spread farther and faster than they fully understood. That expansion succeeded, but it came at a cost: much of the technology that holds the galaxy together can no longer be rebuilt from first principles.

At the center of galactic civilization is the Continuum. The Continuum is a vast governmental and logistical authority whose primary purpose is continuity: maintaining trade lanes, enforcing safety standards, allocating scarce resources, and ensuring that critical infrastructure continues to function. It is not omnipresent, and it is not all-powerful. In the core systems, its presence is visible and structured. On the outer fringes, it is distant, intermittent, and often felt only indirectly.

For generations, the Continuum has been engaged in a long-running war far from the frontier worlds. The details of the conflict are not widely discussed on the fringes, but its effects are felt everywhere. Ships, weapons, reactors, and AI systems consume enormous amounts of power, and the most valuable power source in the galaxy—Starfire energy—is finite. To keep the war effort supplied, the Continuum tightly controls the production and distribution of Starfire cores.

For most frontier citizens, this war is background noise. Life continues. Mining outposts operate. Trade flows. Shuttles come and go on fixed routes. But when someone tries to step beyond the ordinary—when they attempt to acquire long-range ships, high-output reactors, or unrestricted Starfire technology—the Continuum suddenly becomes very real. Not as a villain, but as a barrier: credits alone are not enough when power itself is rationed.

The galaxy endures not because it is thriving, but because it has learned to keep going. Systems are patched instead of replaced. Old machines are maintained long past their intended lifespans. The Continuum does not represent progress so much as inertia—the collective decision that it is safer to keep things running than to risk breaking what still works.
