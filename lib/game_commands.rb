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
      when "desc"
        return if text == ""
        desc text
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


end
