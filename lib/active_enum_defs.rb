require 'active_enum'

ActiveEnum.setup do |config|
  # Extend classes to add enumerate method
  config.extend_classes = [ActiveRecord::Base]

  # Return name string as value for attribute method
  config.use_name_as_value = false

  # Storage of values (:memory, :i18n)
  # config.storage = :memory
end

ActiveEnum.define do
  ACTION_LITERAL = 1
  ACTION_GET = 2
  ACTION_DROP = 3
  ACTION_HIT = 4
  ACTION_MISS = 5
  ACTION_EXIT_ROOM = 6
  ACTION_ENTER_ROOM = 7
  ACTION_EXIT_GAME = 8
  ACTION_ENTER_GAME = 9
  ACTION_FOLLOW = 10
  ACTION_STOP_FOLLOW = 11
  ACTION_TELEPORT_EXIT = 12
  ACTION_TELEPORT_ENTER = 13
  ACTION_EXIT_CREATE_EXIT = 14
  ACTION_ENTER_CREATE_EXIT = 15
  ACTION_SAY = 16
  ACTION_YELL = 17
  ACTION_TELL = 18
  ACTION_UPDATE_ROOM_DESC = 19
  ACTION_CREDITS = 20
  ACTION_SPAWN_CREATURE = 21
  ACTION_SPAWN_OBJECT = 22
  ACTION_DIE = 23

  enum(:action) do
    value id: ACTION_LITERAL, name: "Literal text to be printed on player's screens"
    value id: ACTION_GET, name: 'Get object in room'
    value id: ACTION_DROP, name: 'Drop object in room'
    value id: ACTION_HIT, name: 'Entity hit another entity'
    value id: ACTION_MISS, name: 'Entity missed hitting another entity'
    value id: ACTION_EXIT_ROOM, name: 'Entity went a specific direction and left the room'
    value id: ACTION_ENTER_ROOM, name: 'Entity entered the room from another direction'
    value id: ACTION_EXIT_GAME, name: 'Player left the room by leaving the game'
    value id: ACTION_ENTER_GAME, name: 'Player entered the room by entering the game'
    value id: ACTION_FOLLOW, name: 'Entity began following another entity'
    value id: ACTION_STOP_FOLLOW, name: 'Entity stopped following another entity'
    value id: ACTION_TELEPORT_EXIT, name: 'Entity teleported out of the room'
    value id: ACTION_TELEPORT_ENTER, name: 'Entity teleported into the room'
    value id: ACTION_EXIT_CREATE_EXIT, name: 'Player created an exit and left the room in that direction'
    value id: ACTION_ENTER_CREATE_EXIT, name: 'Player created an exit and entered the room from that direction'
    value id: ACTION_SAY, name: 'Player says something in a room'
    value id: ACTION_YELL, name: 'Player yells something to nearby rooms'
    value id: ACTION_TELL, name: 'Player says something to a specific player in a room'
    value id: ACTION_UPDATE_ROOM_DESC, name: 'Player updated the room description'
    value id: ACTION_CREDITS, name: ''
    value id: ACTION_SPAWN_CREATURE, name: 'Game spawned a new creature in a room'
    value id: ACTION_SPAWN_OBJECT, name: 'Game spawned a new object in a room'
    value id: ACTION_DIE, name: 'Entity died'
  end

  SENDER_TYPE_PLAYER = 1
  SENDER_TYPE_NPC = 2
  SENDER_TYPE_CREATURE = 3
  SENDER_TYPE_ROOM = 4
  SENDER_TYPE_OBJECT = 5

  enum(:sender_type) do
    value id: SENDER_TYPE_PLAYER, name: 'Message sender is a human player'
    value id: SENDER_TYPE_NPC, name: 'Message sender is an NPC'
    value id: SENDER_TYPE_CREATURE, name: 'Message sender is a creature'
    value id: SENDER_TYPE_ROOM, name: 'Message sender is a room'
    value id: SENDER_TYPE_OBJECT, name: 'Message sender is an object'
  end

end
