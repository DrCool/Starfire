require 'tribe'
require '../lib/actable'

class CreatureInstance < ActiveRecord::Base
  include Tribe::Actable
  include Lands::Actable

  belongs_to :creature
  belongs_to :room
  after_initialize :after_initialize
  @event_q = []

  def after_initialize
    options = {
      :name => self.creature_name
    }
    begin
      init_actable options
    rescue Tribe::RegistryError
    end
  end

  def article
    "the "
  end

  def indef_article
    self.creature_name[0] =~ /[aeiouAEIOU]/ ? "an " : "a "
  end

  def process_event(event)
  	case event.action
    when ACTION_HIT
      self.receive_attack(event) if event.data[:recipient_name] == self.creature_name
    when ACTION_MISS
      self.receive_miss(event) if event.data[:recipient_name] == self.creature_name
    when ACTION_DIE
      if event.data[:recipient_name] != self.creature_name
      	# if the player died that this creature was battling, stop attacking.
      end
    end
  end

  def receive_attack(event)
  	self.hp = self.hp - event.data[:damage]
  	if self.hp <= 0
      died(event)
  	else
      self.save
      attack event.data[:attacker]
  	end
  end

  def receive_miss(event)
  	puts "Received miss from #{event.data[:attacker_name]}."
    attack event.data[:attacker]
  end

  def attack(recipient)
    damage = (rand * (self.creature.hitmax.to_f / 3.to_f)).round
    if damage > 0
      World::Manager.room_event(Event.new({
        action: ACTION_HIT,
        room: self.room,
        creature: self,
        data: { attacker: self, attacker_name: self.creature.name, recipient: recipient, recipient_name: recipient.name, damage: damage },
        sender_type: SENDER_TYPE_CREATURE
      }))
    else
      miss(recipient)
    end
  end

  def miss(recipient)
    World::Manager.room_event(Event.new({
      action: ACTION_MISS,
      room: self.room,
      creature: self,
      data: { attacker: self, attacker_name: self.creature.name, recipient: recipient, recipient_name: recipient.name },
      sender_type: SENDER_TYPE_CREATURE
    }))
  end

  def died(event)
    room = Room.find(self.room.id)
    id = self.creature.id
    World::Manager.room_event(Event.new({
      action: ACTION_DIE,
      room: room,
      creature_id: id,
      data: { attacker: event.data[:attacker], recipient_def_article: self.article, attacker_name: event.data[:attacker_name], recipient_name: event.data[:recipient_name] },
      sender_type: SENDER_TYPE_CREATURE
  	}))
    self.destroy
  end


  private

  def on_timer(event)
  end
end
