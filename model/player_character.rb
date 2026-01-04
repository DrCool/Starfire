require_relative '../model/event'

class PlayerCharacter < ActiveRecord::Base
	attr_accessor :client # contains the player's socket connection for things like @client.puts "text"
	@client = nil

	belongs_to :room
	belongs_to :user


  def article
    ""
  end

  def logout_player
    World::Manager.room_event(Event.new({
    	action: ACTION_EXIT_GAME,
    	room: self.room,
    	message: "#{self.name} quit the game.",
    	player: self
  	}))

    $online_players = $online_players.reject { |p| self.name == p.get_player.name }
  end

  def attack(recipient, recipient_type)
    #damage = (rand * self.level * 1.8)) + (1 - self.strength / 8).to_i
    new_dmg = (rand * ((self.level + 1) ** 1.15)).to_i # new_dmg is an alternate calculation that may be better
    #new_dmg = (new_dmg * (self.strength-10) * 0.87).to_i
    #damage = 0 if self.level < 3 and rand > self.level / 10

    damage = new_dmg
    damage = 2 #######################################

    if damage > 0
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
  	overprint.call "#{event.data[:attacker].article.capitalize}#{data[:attacker_name]} #{attack_verb} you for #{data[:damage]} damage!"
  	self.hp = self.hp - data[:damage]
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

  private

  def print(text)
  	@client.print text
  end

end

