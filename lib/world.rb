module World
  class OnlinePlayers
    include Enumerable
    attr_accessor :player, :socket, :thread

    def initialize(socket, thread)
      @player = nil
      @socket = socket
      @thread = thread
    end

    def set_player(player)
      @player = player
    end

    def get_player
      @player
    end

    def get_socket
      @socket
    end

    def get_thread
      @thread
    end

    def notify(message)
      @thread[:q] << message
    end

    def add_event(event)
      @thread[:event_q] << event
    end

    def <<(player)
      self.new(player, self)
    end

    def each(&block)
      if block_given?
        block.call(@player, @thread, @socket)
      else
        to_enum(:each) # allow .each enumerator to be chainable
      end
    end
  end


  class Manager
    def self.run_custom_code(code, player)
      s = TCPSocket.new 'localhost', 2200
      payload = self.build_payload(player)
      ap payload
      s.puts "payload = " + payload.to_json + "\r\n"
      s.puts code + "\r\nEND"
      response = ""
      while line = s.gets
        response = response + line
      end
      s.close
      JSON.parse(response)
    end

    def self.build_payload(player)
      {
        player: player,
        room: player.room,
        user: player.user
      }
    end


    def self.instantiate_npcs
      $npcs = NPC.all
    end

    def self.instantiate_creatures

    end

    def self.logout_all_players
      players = PlayerCharacter.where(logged_in: true).all
      pp = []
      players.each do |player|
        player.logged_in = false
        pp << player
      end
      PlayerCharacter.import pp, on_duplicate_key_update: [:logged_in]
    end

    def self.in_room_players(x, y, z)
      players = PlayerCharacter.where(room_id: @room.id, logged_in: true).all
    end

    def self.notify_room(from_player = nil, text, x, y, z)
      $online_players.each do |player_obj|
        player = player_obj.get_player
        if player.present? && player.x == x && player.y == y && player.z == z && player.logged_in
          player_obj.notify(text) if player.name != from_player
        end
      end
    end

    def self.room_event(event)
      $spawner.process_event(event)

      room_id = event.room.id
      from_player = event.player.name if event.player.present?
      $online_players.each do |player_obj|
        player = player_obj.get_player
        if player.present? && player.room_id == room_id && player.logged_in && player.name != from_player
          player_obj.add_event(event)
        end
      end

      # Reloading the Room every time an event is processed is expensive but prevents a nasty bug.
      # To fix this in the future, keep a hash that is a source of truth and keep it
      # up to date based on room events.
      # TIP: Do NOT use "room = event.room" as this caused a big problem earlier when creatures died and then
      # the room_event tried to send a notification to the creature that died and was already destroyed.
      room = Room.find(room_id)
      room.creature_instances.each {|creature| creature.process_event(event) }
      room.npc.each {|npc| npc.process_event(event) }
    end

    def self.notify_user(to_player, text)
      $online_players.each do |player_obj|
        player = player_obj.get_player
        if player.name == to_player
          player_obj.notify(text)
        end
      end
    end

    def self.dir_list
      [
        { n: {x:  0, y: -1, z:  0, from_dir: "the south", to_dir: "north", to_dir_verbose: "to the north" } },
        { s: {x:  0, y:  1, z:  0, from_dir: "the north", to_dir: "south", to_dir_verbose: "to the south" } },
        { w: {x: -1, y:  0, z:  0, from_dir: "the east",  to_dir: "west",  to_dir_verbose: "to the west"  } },
        { e: {x:  1, y:  0, z:  0, from_dir: "the west",  to_dir: "east",  to_dir_verbose: "to the east"  } },
        { u: {x:  0, y:  0, z: -1, from_dir: "below",     to_dir: "up",    to_dir_verbose: "above"        } },
        { d: {x:  0, y:  0, z:  1, from_dir: "above",     to_dir: "down",  to_dir_verbose: "below"        } },
      ]
    end

    def self.get_vector(dir)
      return {} if dir.blank?
      self.dir_list.find { |e| e.has_key?(dir.to_sym) }.values.first
    end
  end
end
