class Event
  attr_accessor :options
  attr_accessor :action
  attr_accessor :sender_type # player? NPC? creature? object? room?
  attr_accessor :message
  attr_accessor :room
  attr_accessor :player
  attr_accessor :attack_damage
  attr_accessor :creature_id
  attr_accessor :data


  # example:
  # event = Event.new({ action: ACTION_EXIT_ROOM, room: Room.first,
  #           message: "Aaron just went north.", data: { to_dir: "n"}, player: PlayerCharacter.first})

  def initialize(options)
    @options = options
    @action = options[:action]
    @sender_type = options[:sender_type]
    @message = options[:message]
    @room = options[:room]
    @player = options[:player]
    @attack_damage = options[:attack_damage]
    @data = options[:data]
    @creature_id = options[:creature_id]
  end

end
