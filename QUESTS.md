# Quest System Overview (Starfire MUD)

This document describes the **quest system database schema** and how quests are defined, progressed, and reacted to in the game world.

The quest system is designed to support:
- simple starter quests (kill, fetch, escort, repair)
- multi-step narrative quests
- late-game epic quests (e.g. *The Broken Star*)
- per-character quest progress
- NPC and room reactions via quest flags  
  without requiring global world-state changes.

---

## Core Concepts

- **Quest**: a reusable definition (what the quest is)
- **Quest Step**: an ordered stage in a quest
- **Quest Objective**: a concrete requirement (kill, collect, talk, etc.)
- **Character Quest**: a specific character’s run of a quest
- **Objective Progress**: per-character progress tracking
- **Character Flags**: durable per-character markers used for reactions, gating, and unlocks

Quests create **situations**, not permanent world changes.

---

## Table Summary

### `quests`
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

---

### `quest_steps`
Defines ordered stages within a quest.

- A quest has 1+ steps
- Steps are completed sequentially
- Steps can optionally set flags when they start or finish

**Key columns**
- `step_number`: order within the quest (1, 2, 3, …)
- `on_start_flags_json`: flags to set when step begins
- `on_complete_flags_json`: flags to set when step completes

---

### `quest_objectives`
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

---

### `character_quests`
Tracks a character’s participation in a quest.

- One row per character per quest
- Represents a “run” of the quest

**Key columns**
- `character_id`: references `player_characters.id`
- `quest_id`: which quest
- `state`: active | completed | failed | abandoned
- `current_step_number`: which step the character is on
- `started_at`, `completed_at`
- `cooldown_until`: for repeatable quests

---

### `character_quest_objectives`
Tracks per-character progress for each objective.

- One row per objective per character quest

**Key columns**
- `current_count`: progress counter
- `is_completed`: objective completion flag
- `progress_json`: stores granular details (e.g. which rooms visited)

---

### `quest_rewards`
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

---

### `quest_prerequisites`
Defines requirements before a quest can be started.

**Supported prerequisite types**
- `level`
- `quest_completed`
- `flag`

**Examples**
- Requires level ≥ 20
- Requires another quest to be completed
- Requires a specific character flag

---

## Character Flags (Reactive World Layer)

### `character_flags`
Stores persistent per-character flags.

Flags are used to:
- gate NPC dialogue
- gate room flavor text
- unlock future quests
- track major accomplishments

Flags **do not change the global world state**.

**Key columns**
- `flag_key`: e.g. `quest.kfo.loader_droid.fixed`
- `flag_value`: usually `'1'`
- `set_by_quest_id`: source quest (optional)
- `expires_at`: optional (for timed flags later)

---

## NPC / Room Reactions

NPCs and rooms can react to completed quests using flags.

### Gating fields added to existing tables
- `npc_sayings.requires_flag_key`
- `npc_sayings.requires_flag_value`
- `npc_sayings.once_per_player`
- `room_sayings.requires_flag_key`
- `room_sayings.requires_flag_value`
- `room_sayings.once_per_player`

Sayings are shown **only if the character has the required flag**.

---

### `character_seen_sayings`
Tracks one-time NPC or room lines already seen by a character.

Used when `once_per_player = 1`.

---

## Quest Progress Model (Runtime)

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

---

## Design Rules

- Quests are **per-character**, not global
- Flags affect **perception and access**, not world permanence
- Steps and objectives are data-driven
- New quest types should not require schema changes
- Complex quests (e.g. *The Broken Star*) are built by combining steps and objectives

---

## Example Flag Naming Convention
Flags follow a hierarchical dot-separated format:
`quest.<quest_key>.<descriptive_suffix>`

The `<descriptive_suffix>` should describe a durable outcome or unlock, not transient progress (e.g. use `.completed`, `.fixed`, `.unlocked`).

Examples:
- `quest.kfo.loader_droid.fixed`
- `quest.kfo.vermin.completed`
- `quest.ship.private_unlock`

---

## Intended Use

This system supports:
- basic starter quests
- scalable difficulty by location and level
- NPC acknowledgment of player actions
- late-game, multi-stage epic quests
- future automation or generation of quests via Codex