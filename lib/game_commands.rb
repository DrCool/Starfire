module GameCommands

  def process_response_commands(commands)
    return if commands.empty?
    flag_print_location = false

    print commands["print"] if commands["print"]

    set = commands["set_player"]

    set.each do |cmd|
      key_val = cmd.to_a[0]
      ap key_val
      ap @player.room_id
      if cmd.key?("room_id")
        @player.update_attribute(key_val.first, key_val.second)
        room = Room.find(key_val.second)
        load_room(room.x, room.y, room.z)
        flag_print_location = true if cmd.key?("room_id")
      else
        # ...
      end

    end

    print_location if flag_print_location
  end

  def parse_input(full_command)
    @command = full_command
    args = full_command.split(" ")
    command = args.shift
    text = args.join(' ')

    puts command

    # Process the simple one-letter commands first so they don't accidentally match a custom room command
    case command
      when "n", "s", "w", "e", "u", "d"
        dir command
        return
    end

    # Check if custom command is available from the room, an object, or an NPC.
    # This should be done first so it can override anything below.

    room_custom = CustomCommand.where(codable_type: "Room").where(codable_id: @room.id).where(is_active: true).first # check for custom room command
    if room_custom.present?
      if room_custom.command_text.include?(full_command) or room_custom.synonym_commands.include?(full_command)
        result = World::Manager.run_custom_code(room_custom.code, @player)
        puts "Result of running custom code:"
        p result

        if result['error']
          print "Command not understood."
          print "Error: #{result['error']}"
        else
          process_response_commands(result["result"])
        end

#        events = result["events"]
#        # ... process events, if any
#        if events.present?
#          events.each do |event|
#            
#          end
#        end
        return
      end
    end

    # Check for custom object command by iterating through each item of inventory
    # .....

    case command
      when "quit"
        @message_thread.exit
        quit
      when "form"
        data = [
          {
            name: "Name:      ",
            type: FIELD_TYPE_STRING,
            value: {
              max_display_chars: 15,
              existing_value: "gun",
            }
          },
          {
            name: "Value:     ",
            type: FIELD_TYPE_INTEGER,
            value: {
              max_display_chars: 5,
              existing_value: 25,
            }
          },
          {
            name: "Weight:    ",
            type: FIELD_TYPE_INTEGER,
            value: {
              max_display_chars: 5,
              existing_value: 3,
            }
          },
          {
            name: "Wieldable: ",
            type: FIELD_TYPE_BOOLEAN,
            value: {
              existing_value: false,
            }
          },
          {
            name: "Wearable:  ",
            type: FIELD_TYPE_BOOLEAN,
            value: {
              existing_value: false,
            }
          },
          {
            name: " SAVE ",
            type: FIELD_TYPE_SAVE
          },
          {
            name: " CANCEL ",
            type: FIELD_TYPE_CANCEL
          }
        ]
        form(data)

        return
      when "test"
        result = scrolling_menu
        ap "User chose option: #{result}"
        return
      when "loc"
        loc
        return
      when "who"
        who
        return
      when "room-say"
        room_say text
        return
      when "look"
        print_location(verbose: true)
        return
      when "inv", "inventory"
        show_inventory
        return
      when "desc"
        return if text == ""
        desc text
        return
      when "stats"
        stats
        return
      when "board"
        board_ship
        return
      when "leave"
        leave_ship
        return
      when "reload"
        load "#{File.dirname(__FILE__)}/lands.rb"
        load "#{File.dirname(__FILE__)}/game_commands.rb"
        print "Code reloaded."
        return
      when "npc-new"
        npc_new
        return
      when "hit", "attack", "kill"
        hit text
        return
      when "say"
        say text
        return
      when "get"
        get_item text
        return
      when "search"
        search_item text
        return
      when "hea", "health"
      	print "Your health: #{@player.hp} / #{@player.hitmax}"
      	return
      when "rest"
      	if @player.hp == @player.hitmax
      		print "You are fully rested."
      		return
      	end
      	@player.hp += 1
      	print "You feel more rested."
      	return
    	when "exa", "examine"
    		entity = find_entity_in_room(text)
        if entity.present?
    		case entity[:type]
    		when :npc
            npc = entity[:entity]
            print npc.description
            print "#{npc.npc_name} health: [#{npc.hp} / #{npc.hitmax}]"
      			return
      		when :creature
      			creature_instance = entity[:entity]
            creature_instance.reload
      			ap "**************************"
      			ap entity
      			ap "**************************"
      			print creature_instance.creature.description
      			print "#{creature_instance.creature_name.capitalize} health: [#{creature_instance.hp} / #{creature_instance.creature.hitmax}]"
      			return
      		when :object
      			return
      		when :prop
      			return
          when :corpse
            print "It's a corpse. You can type 'search corpse' to see if it has any items or objects you can take."
            return
      		end
        end
    		print "There isn't #{vanna(text)} here."
    		return


    end

    if command[0...1] == "."
      create_new_exit(command[1...2])
      return
    end

    print "Command not understood."
  end




	def quit
		save_player
		print $pastel.bright_red("Thanks for playing!")
		@player.logout_player
		@client.close
		Thread.current.exit
	end

	def loc
		print "You are located at #{@player.x} / #{@player.y} / #{@player.z}."
	end

	def who
		who = User.get_logged_in_users
		who = who.pluck(:name)
		print "CURRENTLY ONLINE:"
		print "* " + who.join("\n\r* ")
	end

	def save_player
		@player.save
	end

	def hit(text)
		print "Hit who?" and return if text == ""

		entity = find_entity_in_room(text)
		if entity.nil?
			print "There isn't #{vanna(text)} here."
		else
			recipient_type = entity[:type]
			if recipient_type == :creature
				entity = entity[:entity]
				@player.attack entity, recipient_type
      elsif recipient_type == :npc
        npc = entity[:entity]
        print npc.not_attackable_message and return if not npc.attackable
			else
				print "You can't attack that."
			end
		end
	end

  def say(text)
    World::Manager.room_event(Event.new({
      action: Event.action[:say],
      room: self.room,
      data: { sender_name: @player.name, text: text },
      player: @player,
      sender_type: Event.sender_type[:player]
    }))
    # Maybe rewrite the previous line to say:  You say, "Hello everyone."
    #print "Everyone in the room heard you."
	end

  def show_inventory
    items = InventoryItem.where(owner_type: "PlayerCharacter", owner_id: @player.id).includes(:game_object)
    credits = @player.credits.to_i

    if credits == 0 && items.empty?
      print "You are carrying nothing."
      return
    end

    print "You are carrying:"
    if credits > 0
      credit_line = credits == 1 ? "1 credit" : "#{credits} credits"
      print "* #{credit_line}"
    end

    items.each do |item|
      obj = item.game_object
      next if obj.nil?

      quantity = item.quantity.to_i
      if quantity > 1
        print "* #{quantity} #{obj.name}"
      else
        print "* #{obj.name}"
      end
    end
  end

  def search_item(text)
    if text.strip == ""
      print "Search what?"
      return
    end

    if text.downcase.include?("corpse")
      search_corpse
      return
    end

    print "You don't see anything like that to search."
  end

  def search_corpse
    corpse = Corpse.where(room_id: @room.id).order(:created_at).first
    if corpse.nil?
      print "There isn't a corpse here."
      return
    end

    if corpse.expires_at.present? && Time.now > corpse.expires_at
      corpse.destroy
      print "The corpse has already decayed."
      return
    end

    drop_corpse_items(corpse)
    corpse.destroy
    print "You search the corpse."
    print_location
  end

  def drop_corpse_items(corpse)
    InventoryItem.where(owner_type: "Corpse", owner_id: corpse.id).find_each do |item|
      drop_inventory_item(item, "Room", @room.id)
    end

    credits = corpse.credits.to_i
    return if credits <= 0

    @room.update!(credits_on_ground: @room.credits_on_ground.to_i + credits)
  end

  def get_item(text)
    if text.strip == ""
      print "Get what?"
      return
    end

    text = text.strip
    if text == "all"
      get_all_items
      return
    end

    if text == "credits"
      pickup_credits
      return
    end

    inventory_item = find_room_item(text)
    if inventory_item.nil? || inventory_item[:type] != :object
      print "There isn't #{vanna(text)} here."
      return
    end

    take_room_item(inventory_item[:entity])
  end

  def get_all_items
    picked_any = false

    if @room.credits_on_ground.to_i > 0
      pickup_credits
      picked_any = true
    end

    items = InventoryItem.where(owner_type: "Room", owner_id: @room.id).includes(:game_object)
    items.each do |item|
      take_room_item(item)
      picked_any = true
    end

    print "There is nothing here to pick up." unless picked_any
  end

  def pickup_credits
    credits = @room.credits_on_ground.to_i
    if credits <= 0
      print "There are no credits here."
      return
    end

    @room.update!(credits_on_ground: 0)
    @player.update!(credits: @player.credits.to_i + credits)
    print "You pick up #{credits} credits."
  end

  def take_room_item(item)
    obj = item.game_object
    if obj.nil?
      item.destroy
      return
    end

    drop_inventory_item(item, "PlayerCharacter", @player.id)
    print "You pick up #{obj.name}."
  end

  def drop_inventory_item(item, new_owner_type, new_owner_id)
    existing = InventoryItem.where(
      owner_type: new_owner_type,
      owner_id: new_owner_id,
      object_id: item.object_id
    ).first

    if existing.present?
      existing.update!(quantity: existing.quantity.to_i + item.quantity.to_i)
      item.destroy
    else
      item.update!(owner_type: new_owner_type, owner_id: new_owner_id)
    end
  end


end
