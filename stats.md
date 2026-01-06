# Stats & Combat Calculations

This document describes how character stats currently influence combat and progression in StarFire.

## Core Stats

- **Level**: Overall character progression tier. Used for gating equipment via `required_level`.
- **Experience**: Earned from defeating creatures. See XP formula below.
- **Health (hp / hitmax)**: Current and maximum hit points.
- **Strength**: Adds a flat bonus to weapon damage.
- **Dexterity**: Improves hit chance.
- **Bravery**: Currently displayed, not used in calculations yet.

## Attack Resolution (Player Attacking a Creature)

1. **Hit chance**:
   - `hit_chance = min(65 + (dexterity * 2), 95)`
   - A roll of `rand(100)` under `hit_chance` results in a hit.

2. **Damage**:
   - Weapon damage roll: `rand(damage_min..damage_max)`
   - Strength bonus: `floor(strength / 4)`
   - Final damage: `weapon_damage + strength_bonus`, minimum of **1**

## Defense (Player Receiving Damage)

- Torso armor mitigates damage with a flat reduction:
  - `mitigated = incoming_damage - armor_rating`
  - Minimum of **1** damage always applies.

## Experience Gain (Creature Kill)

Experience is awarded to the player who delivers the killing blow.

**Formula**:

```
base = (creature.hitmax / 2.0) + (creature.strength / 4.0) + (creature.dexterity / 4.0)
base = max(round(base), 1)
variance = rand(0..(base * 0.2).round)
experience_awarded = base + variance
```

This yields a small random variance (up to 20%) to avoid deterministic XP values while still scaling with creature difficulty.

## Equipment Notes

- **Weapons** use the `objects` fields `damage_min` / `damage_max`.
- **Torso armor** uses `objects.armor_rating`.
- Equipment is gated by `objects.required_level`.

## Future Extensions

Potential future additions include:

- Bravery checks for fleeing or intimidation.
- Crit chance or accuracy bonuses.
- Additional armor slots (head/legs) and ranged accuracy tiers.
