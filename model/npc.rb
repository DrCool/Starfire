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

  def article
    ""
  end

  def load_sayings
    if self.room
      @sayings = NPCSaying.where(npc_id: self.id, only_in_x: self.room.x, only_in_y: self.room.y, only_in_z: self.room.z).pluck(:text)
    end
  end

  def load_movements
    @movements = NPCMovement.where(npc_id: self.id)
  end

  def after_initialize
    @sayings = []
    @movements = []
    load_sayings
    load_movements

    options = {
      :name => self.npc_name
    }
    @saying_index = 0

    begin
      init_actable options
    rescue Tribe::RegistryError
    end
  end

  def begin_saying_timer
    timer!(8, :timer, "saying") if $0 != "irb"
  end

  def begin_movement_timer(interval)
    timer!(interval, :timer, "movement") if $0 != "irb"
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
    if event.data == "saying" and @sayings.present?
      World::Manager.room_event(Event.new({
        action: ACTION_LITERAL,
        room: self.room,
        message: @sayings[@saying_index],
        npc: self,
        sender_type: SENDER_TYPE_NPC
      }))

      @saying_index = @saying_index + 1
      @saying_index = 0 if @saying_index >= @sayings.count
      begin_saying_timer
    end

    if event.data == "movement"
      room_movement = @movements.find_by(room_id: self.room_id)
      dir = room_movement.can_go.split('').shuffle.first
      vector = World::Manager.get_vector(dir)

      World::Manager.room_event(Event.new({
        action: ACTION_EXIT_ROOM,
        room: self.room,
        message: "#{self.npc_name} went #{vector[:to_dir]}.",
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
        message: "#{self.npc_name} entered from #{vector[:from_dir]}.",
        data: vector,
        npc: self,
        sender_type: SENDER_TYPE_NPC
      }))

      load_sayings # load new npc sayings for this room, if any

      room_movement = @movements.find_by(room_id: new_room.id)
      interval = rand(room_movement.min_wait..room_movement.max_wait)
      begin_movement_timer(interval)
    end
  end

  def on_initialize(event)
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
