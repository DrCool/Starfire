require 'tribe'
require_relative '../lib/actable'
require_relative '../lib/quest_progression'
require_relative '../model/player_character'

class CreatureInstance < ActiveRecord::Base
  include Tribe::Actable
  include Lands::Actable

  belongs_to :creature
  belongs_to :room
  has_many :inventory_items, -> { where owner_type: "CreatureInstance" }, foreign_key: :owner_id
  after_initialize :after_initialize
  after_create :assign_spawn_loot
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
        data: { attacker: self, attacker_name: self.creature.name, attack_verb: self.creature.attack_verb, recipient: recipient, recipient_name: recipient.name, damage: damage },
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
    award_experience(event)
    create_corpse_for_room(room)
    if event.data[:attacker].is_a?(PlayerCharacter)
      quest_event = Event.new({
        action: ACTION_DIE,
        room: room,
        creature_id: id,
        data: event.data.merge(quest_progressed: true, creature_instance_id: self.id),
        sender_type: SENDER_TYPE_CREATURE
      })

      World::QuestProgression.new(event.data[:attacker]).handle_creature_death(quest_event)
    end
    World::Manager.room_event(Event.new({
      action: ACTION_DIE,
      room: room,
      creature_id: id,
      data: { attacker: event.data[:attacker], recipient_def_article: self.article, attacker_name: event.data[:attacker_name], recipient_name: event.data[:recipient_name], quest_progressed: true },
      sender_type: SENDER_TYPE_CREATURE
  	}))
    self.destroy
  end


  private

  def assign_spawn_loot
    loot_rows = CreatureLoot.where(creature_id: creature_id)
    loot_rows.each do |loot|
      next unless loot_drop?(loot.drop_chance)

      quantity = rand(loot.min_quantity..loot.max_quantity)
      next if quantity <= 0

      InventoryItem.create!(
        owner_type: "CreatureInstance",
        owner_id: id,
        object_id: loot.object_id,
        quantity: quantity
      )
    end
  end

  def loot_drop?(drop_chance)
    chance = drop_chance.to_f
    return true if chance >= 1
    return false if chance <= 0

    rand < chance
  end

  def create_corpse_for_room(room)
    corpse = Corpse.create!(
      room_id: room.id,
      creature_instance_id: id,
      credits: credits.to_i,
      expires_at: 120.seconds.from_now
    )

    InventoryItem.where(owner_type: "CreatureInstance", owner_id: id).find_each do |item|
      item.update!(owner_type: "Corpse", owner_id: corpse.id)
    end
  end

  def on_timer(event)
  end

  def award_experience(event)
    attacker = event.data[:attacker]
    return unless attacker.is_a?(PlayerCharacter)

    attacker.award_experience_for(self)
  end
end
