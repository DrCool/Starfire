require 'tribe'
require_relative '../lib/world'
require_relative '../lib/actable'
require_relative './event'

class NPC < ActiveRecord::Base
  include Tribe::Actable
  include Lands::Actable

  self.table_name = :npc

  belongs_to :room
  has_many :npc_sayings
  has_many :npc_movements
  has_one :user, primary_key: :created_by, foreign_key: :id

  after_initialize :after_initialize

  # Shared, per-player-per-room rate limiter for NPC sayings.
  # Keeps crowded rooms readable without changing movement events.
  SAYING_LIMIT_15S = 2
  SAYING_LIMIT_60S = 5
  SAYING_WINDOW_15S = 15
  SAYING_WINDOW_60S = 60

  @@saying_rate_log = {} # key => Array<Time>

  def self.allow_npc_saying?(player_id, room_xyz_hash)
    return true if player_id.nil? || room_xyz_hash.nil?

    now = Time.now
    key = "#{player_id}|#{room_xyz_hash}"
    arr = (@@saying_rate_log[key] ||= [])

    # Drop timestamps older than the largest window to keep memory bounded.
    cutoff = now - SAYING_WINDOW_60S
    arr.reject! { |t| t < cutoff }

    count_15 = arr.count { |t| t >= now - SAYING_WINDOW_15S }
    return false if count_15 >= SAYING_LIMIT_15S

    count_60 = arr.length
    return false if count_60 >= SAYING_LIMIT_60S

    arr << now
    true
  end

  def self.clear_saying_rate_for_room(player_id, room_xyz_hash)
    return if player_id.nil? || room_xyz_hash.nil?
    key = "#{player_id}|#{room_xyz_hash}"
    @@saying_rate_log.delete(key)
  end

  def article
    ""
  end

  def load_sayings_for_player(player)
    return unless self.room
    return unless player

    pid = player.id

    # Pull room-specific sayings and global sayings (no location constraints).
    room_sayings = NPCSaying.where(
      npc_id: self.id,
      only_in_x: self.room.x,
      only_in_y: self.room.y,
      only_in_z: self.room.z
    ).pluck(:text)

    global_sayings = NPCSaying.where(
      npc_id: self.id,
      only_in_x: nil,
      only_in_y: nil,
      only_in_z: nil
    ).pluck(:text)

    sayings = (room_sayings + global_sayings).compact

    # Replace [color]...[/color] tags with Pastel styles
    sayings.map! do |saying|
      saying.gsub(/\[([a-zA-Z0-9_]+)\](.*?)\[\/\1\]/m) do
        style = Regexp.last_match(1).to_sym
        content = Regexp.last_match(2)
        if $pastel.respond_to?(style)
          $pastel.public_send(style, content)
        else
          content
        end
      end
    end

    @sayings_by_player[pid] = sayings

    state = @saying_state_by_player[pid]

    # Reset per-player cursor if first time, or if the NPC moved rooms since last time we loaded.
    if state.nil? || state[:xyz_hash] != self.room.xyz_hash
      @saying_state_by_player[pid] = {
        index: 0,
        exhausted: sayings.blank?,
        xyz_hash: self.room.xyz_hash
      }
    else
      # If sayings were previously exhausted for this room, keep exhausted.
      # If they were not exhausted but the list changed length, clamp index.
      if !state[:exhausted] && state[:index] >= sayings.length
        state[:index] = 0
      end
    end

    sayings
  end

  def load_movements
    @movements = NPCMovement.where(npc_id: self.id)
  end

  def after_initialize
    @sayings_room = []
    @saying_index_room = 0
    @sayings_exhausted_room = true

    @movements = []

    load_movements

    options = {
      :name => self.npc_name
    }
    @saying_state_by_player = {}
    @sayings_by_player = {}

    begin
      init_actable options
    rescue Tribe::RegistryError
    end
  end

  def begin_saying_timer_for_player(player)
    return unless player
    pid = player.id
    state = @saying_state_by_player[pid]
    return if state.nil? || state[:exhausted]

    delay = 11 + rand(0..10)
    # Use a string payload because some timer backends do not preserve Hash data.
    timer!(delay, :timer, "saying|#{pid}") if $0 != "irb"
  end

  def load_sayings_for_room
    return unless self.room

    room_sayings = NPCSaying.where(
      npc_id: self.id,
      only_in_x: self.room.x,
      only_in_y: self.room.y,
      only_in_z: self.room.z
    ).pluck(:text)

    global_sayings = NPCSaying.where(
      npc_id: self.id,
      only_in_x: nil,
      only_in_y: nil,
      only_in_z: nil
    ).pluck(:text)

    sayings = (room_sayings + global_sayings).compact

    sayings.map! do |saying|
      saying.gsub(/\[([a-zA-Z0-9_]+)\](.*?)\[\/\1\]/m) do
        style = Regexp.last_match(1).to_sym
        content = Regexp.last_match(2)
        if $pastel.respond_to?(style)
          $pastel.public_send(style, content)
        else
          content
        end
      end
    end

    @sayings_room = sayings
    @saying_index_room = 0
    @sayings_exhausted_room = sayings.blank?
    sayings
  end

  def begin_saying_timer
    return if @sayings_exhausted_room
    delay = 11 + rand(0..10)
    timer!(delay, :timer, "saying") if $0 != "irb"
  end

  def begin_movement_timer(interval)
    timer!(interval, :timer, "movement") if $0 != "irb"
  end

  def start_sayings_for_player(player)
    load_sayings_for_player(player)
    begin_saying_timer_for_player(player)
  end

  def receive_attack(event)
  end

  def receive_miss(event)
  end

  def attack

  end

  def process_event(event)
  end


  private

  # Tribe events
  def on_timer(event)
    # Player-scoped saying timer (string payload: "saying|<player_id>")
    if event.data.is_a?(String) && event.data.start_with?("saying|")
      pid = event.data.split("|", 2)[1].to_i
      player = User.find_by(id: pid)
      sayings = load_sayings_for_player(player)
      state = @saying_state_by_player[pid]

      if sayings.present? && state && !state[:exhausted]
        # Optional shared rate limiting across NPCs in the same room for this player.
        if !NPC.allow_npc_saying?(pid, self.room&.xyz_hash)
          begin_saying_timer_for_player(player)
          return
        end

        # Deliver atmosphere to this player only.
        World::Manager.player_event(Event.new({
          action: ACTION_LITERAL,
          room: self.room,
          message: sayings[state[:index]],
          npc: self,
          sender_type: SENDER_TYPE_NPC,
          recipient: player
        }))

        state[:index] = state[:index] + 1

        if state[:index] >= sayings.count
          state[:exhausted] = true
        else
          begin_saying_timer_for_player(player)
        end
      end
    end

    # Global (world) saying timer (payload: "saying")
    if event.data == "saying"
      # Optional: if you want global sayings to also be rate-limited per-room, per-player,
      # keep this as a room broadcast only (no per-player limiting here).

      if @sayings_room.present? && !@sayings_exhausted_room
        World::Manager.room_event(Event.new({
          action: ACTION_LITERAL,
          room: self.room,
          message: @sayings_room[@saying_index_room],
          npc: self,
          sender_type: SENDER_TYPE_NPC
        }))

        @saying_index_room += 1
        if @saying_index_room >= @sayings_room.count
          @sayings_exhausted_room = true
        else
          begin_saying_timer
        end
      end
    end

    if event.data == "movement"
      room_movement = @movements.find_by(room_id: self.room_id)
      if room_movement.nil? || room_movement.can_go.empty?
        return
      end
      dir = room_movement.can_go.split('').shuffle.first
      vector = World::Manager.get_vector(dir)

      World::Manager.room_event(Event.new({
        action: ACTION_EXIT_ROOM,
        room: self.room,
        message: $pastel.bright_yellow(self.npc_name) + " went #{vector[:to_dir]}.",
        data: vector, npc: self,
        sender_type: SENDER_TYPE_NPC
      }))

      new_x = self.room.x + vector[:x]
      new_y = self.room.y + vector[:y]
      new_z = self.room.z + vector[:z]
      new_room = Room.find_by(x: new_x, y: new_y, z: new_z)

      self.room = new_room
      self.save

      World::Manager.room_event(Event.new({
        action: ACTION_ENTER_ROOM,
        room: new_room,
        message: $pastel.bright_yellow(self.npc_name) + " entered from #{vector[:from_dir]}.",
        data: vector,
        npc: self,
        sender_type: SENDER_TYPE_NPC
      }))

      # NPC moved rooms; sayings are player-scoped, so clear per-player caches.
      @sayings_by_player = {}
      @saying_state_by_player = {}

      load_sayings_for_room
      begin_saying_timer

      room_movement = @movements.find_by(room_id: new_room.id)
      interval = rand(room_movement.min_wait..room_movement.max_wait)
      begin_movement_timer(interval)
    end
  end

  def on_initialize(event)
    # Start a world-based sayings timer so NPCs are lively even without player-scoped wiring.
    load_sayings_for_room
    begin_saying_timer

    begin_movement_timer(6) if self.can_roam
  end

  def on_exception(event)
  end

  def on_shutdown(event)
  end

  def on_child_died(event)
  end

  def on_child_shutdown(event)
  end

  def on_parent_died(event)
  end

  def on_my_custom(event)
    puts "Custom event: #{event.inspect}"
  end
end
