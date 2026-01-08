# Zones

A `zone` is a collection of interconnected rooms (using the `rooms` table from the database) that share a common theme, environment, or purpose. Zones help organize the game world into manageable sections, each with its own unique atmosphere and challenges.

A zone could be a mining outpost, a derelict spaceship, a bustling spaceport, or a remote research facility. Each zone contains multiple rooms that players can explore, interact with NPCs, and undertake quests within.

Every zone must have, at a minimum, a landing terminal for shuttles and private ships to dock at. This is the way players move around between zones. If a zone will have any combat, it must also have a medbay/hospital for healing, a shop for buying and selling items, and should have a job/bounty board for picking up quests.

When designing zones, consider how they connect to each other, the types of NPCs that inhabit them, and the kinds of quests and activities players can engage in while exploring these areas. Generally, rooms in a zone are around 8-25 rooms in size, but this can vary based on the complexity and purpose of the zone.

Zones are defined in the `zones` table in the database. The zones table is very basic right now, but it can be expanded in the future to include more metadata about each zone.

### `zones` Table

```
CREATE TABLE `zones` (
`id` int(11) unsigned NOT NULL AUTO_INCREMENT,
`name` varchar(255) NOT NULL,
`created_at` datetime DEFAULT NULL,
`updated_at` datetime DEFAULT NULL,
PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8;
```

