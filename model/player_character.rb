require_relative '../model/event'

class PlayerCharacter < ActiveRecord::Base
	attr_accessor :client # contains the player's socket connection for things like @client.puts "text"
	@client = nil

	belongs_to :room
	belongs_to :user
  has_many :inventory_items, -> { where owner_type: "PlayerCharacter" }, foreign_key: :owner_id
  has_many :player_equipment, foreign_key: :player_character_id


  def article
    ""
  end

  def logout_player
    World::Manager.room_event(Event.new({
    	action: ACTION_EXIT_GAME,
    	room: self.room,
    	message: "#{$pastel.bright_yellow(self.name)} left the game.",
    	player: self
  	}))

    $online_players = $online_players.reject { |p| self.name == p.get_player.name }
  end

  def attack(recipient, recipient_type)
    hit_chance = [65 + (self.dexterity.to_i * 2), 95].min
    if rand(100) < hit_chance
      damage = weapon_damage + strength_bonus
      damage = 1 if damage < 1

	    print "You hit #{recipient.article}#{recipient[recipient_type.to_s+"_name"]} for #{damage} damage."
	    World::Manager.room_event(Event.new({
	    	action: ACTION_HIT,
	    	room: self.room,
	    	player: self,
	    	sender_type: SENDER_TYPE_PLAYER,
	    	data: {
	    		attacker: self,
	    		attacker_name: self.name,
	    		recipient: recipient,
	    		recipient_name: recipient[recipient_type.to_s+"_name"],
	    		damage: damage
	    	}
	  	}))
    else
	    print "You missed."
	    World::Manager.room_event(Event.new({
	    	action: ACTION_MISS,
	    	room: self.room,
	    	player: self,
	    	sender_type: SENDER_TYPE_PLAYER,
	    	data: {
	    		attacker: self,
	    		attacker_name: self.name,
	    		recipient: recipient,
	    		recipient_name: recipient[recipient_type.to_s+"_name"]
	    	}
	  	}))
    end
  end

  def receive_attack(event, overprint)
  	data = event.data
    attack_verb = data[:attack_verb] || "hit"
    damage = apply_armor_reduction(data[:damage].to_i)
  	overprint.call "#{event.data[:attacker].article.capitalize}#{data[:attacker_name]} #{attack_verb} you for #{damage} damage!"
  	self.hp = self.hp - damage
  	self.save
  	died(data) if self.hp <= 0
  end

  def receive_miss(event, overprint)
  	overprint.call "#{event.data[:attacker].article.capitalize}#{event.data[:attacker_name]} missed."
  end

  def died(data)
  	print $pastel.bright_red("\r\n\r\n    You have died!\r\n\r\n")
    World::Manager.room_event(Event.new({
    	action: ACTION_DIE,
    	room: self.room,
    	player: self,
    	data: { attacker_name: data[:attacker_name], attacker: data[:attacker], recipient: self, recipient_name: self.name },
    	sender_type: SENDER_TYPE_PLAYER 
  	}))

    print "But for now, your health has been reset to full."
    self.hp = self.hitmax
    self.save
  end

  def award_experience_for(creature_instance)
    amount = experience_for_creature(creature_instance)
    self.experience = self.experience.to_i + amount
    self.save
    print "\r\nYou gain #{amount} experience."
  end

  def weapon_damage
    weapon = equipped_weapon
    min = weapon&.damage_min.to_i
    max = weapon&.damage_max.to_i
    min = 1 if min < 1
    max = min if max < min
    rand(min..max)
  end

  def strength_bonus
    (self.strength.to_i / 4.0).floor
  end

  def apply_armor_reduction(damage)
    armor = equipped_torso_armor
    return damage if armor.nil?

    reduction = armor.armor_rating.to_i
    mitigated = damage - reduction
    mitigated < 1 ? 1 : mitigated
  end

  def equipped_weapon
    entry = PlayerEquipment.find_by(player_character_id: id, slot: "weapon")
    entry&.game_object
  end

  def equipped_torso_armor
    entry = PlayerEquipment.find_by(player_character_id: id, slot: "torso")
    entry&.game_object
  end

  def experience_for_creature(creature_instance)
    creature = creature_instance.creature
    hitmax = creature.hitmax.to_i
    strength = creature.strength.to_i
    dexterity = creature.dexterity.to_i

    base = (hitmax / 2.0) + (strength / 4.0) + (dexterity / 4.0)
    base = base.round
    base = 1 if base < 1

    variance = rand(0..(base * 0.2).round)
    base + variance
  end

  # Provide XP progression helpers on the PlayerCharacter model so any part of the
  # code that has a reference to a player can query/train safely.


  def experience_for_next_level
    # Simple quadratic progression: required XP grows with (level+1)^2 scaled by a base.
    # Using a modest base keeps progression reasonable given the small XP rewards from creatures.
    level = self.level.to_i
    base_xp = 800 # minimum XP required for level 2
    base_xp + ((level ** 1.2) * 200).to_i
  end

  def enough_experience_to_train?
    self.experience.to_i >= experience_for_next_level
  end

  private

  def print(text)
  	@client.print text
  end

end
