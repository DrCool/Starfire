require_relative '../model/zone'
require_relative '../model/room'
require_relative '../model/quest'
require_relative '../model/character_quest'
require_relative '../model/character_flag'
require_relative '../model/character_quest_objective'
require_relative '../model/character_quest_reward'
require_relative '../model/character_quest_step'
require_relative '../model/player_character'
require_relative '../model/quest_flag'
require_relative '../model/quest_prerequisite'
require_relative '../model/quest_objective'
require_relative '../model/quest_reward'
require_relative '../model/quest_step'
require_relative '../model/prop'
require_relative 'quest_progression'
require_relative 'map'
require_relative '../lib/quest_commands'
require 'json'  # added to allow JSON generation

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
      result = scrolling_menu("Test Question", ["Option 1", "Option 2", "Option 3"])
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
    when "follow"
      follow text
      return
    when "unfollow"
      unfollow
      return
    when "desc"
      return if text == ""
      desc text
      return
    when "stats"
      stats
      return
    when "map"
      show_map @room.id, @screen_params
      return
    when "board"
      board_ship text
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
    when "list"
      list_shop_items
      return
    when "buy"
      buy_item text
      return
    when "sell"
      sell_item text
      return
    when "wield"
      wield_item text
      return
    when "unwield"
      unwield_item
      return
    when "wear"
      wear_item text
      return
    when "remove"
      remove_item text
      return
    when "get"
      get_item text
      return
    when "drop"
      drop_item text
      return
    when "give"
      give_item text
      return
    when "search"
      search_item text
      return
    when "hea", "health"
      print "Your health: #{@player.hp} / #{@player.hitmax}"
      return
    when "rest"
      if @player.hp == @player.hitmax
        print "You are FULLY rested."
        return
      end
      @player.hp += 1
      print "You feel more rested."
      return
    when "quests", "jobs"
      if text.to_s.strip == ""
        list_quests
      else
        show_quest_details(text)
      end
      return
    when "accept"
      accept_quest text
      return
    when "journal"
      journal text
      return
    when "complete"
      complete_quest text
      return
    when "create_llm_quest"
      create_llm_quest
      return
    when "exa", "examine"
      entity = find_entity_in_room(text)
      if entity.present?
        if [:prop, :object].include?(entity[:type])
          check_for_quest_objective({
              objective_type: "examine",
              target_type: entity[:type] == :object ? "object" : "prop",
              command_text: text,
              prop: (entity[:type] == :prop ? entity[:entity] : nil),
              object: (entity[:type] == :object ? entity[:entity] : nil)
          })
        end
        case entity[:type]
        when :npc
          npc = entity[:entity]
          print npc.description
          print "#{npc.npc_name} health: [#{npc.hp} / #{npc.hitmax}]"
          return
        when :creature
          creature_instance = entity[:entity]
          creature_instance.reload
          print creature_instance.creature.description
          print "#{creature_instance.creature_name.capitalize} health: [#{creature_instance.hp} / #{creature_instance.creature.hitmax}]"
          return
        when :object
          return
        when :prop
          return
        when :corpse
          print "It's a corpse. You can type 'search corpse' to see if it has any items you can take. After typing 'search corpse', the items or credits will appear in the room. Type 'get <item name>' to pick up any items, or 'get all'."
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

    if command[0...1] == "'"
      say command[1...]
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
    print "Room ID: #{@room.id}"
    print @room.awesome_inspect
  end

  def who
    who = User.get_logged_in_users
    who = who.pluck(:name)
    print "CURRENTLY ONLINE:"
    print "* " + who.join("\n\r* ")
  end

  def resolve_prop_in_room(text)
    return nil if text.to_s.strip.empty?
    return nil unless defined?(Prop)

    downcased = text.to_s.downcase
    if @room.respond_to?(:props)
      @room.props.find { |prop| prop.name.to_s.downcase.include?(downcased) }
    else
      Prop.where(room_id: @room.id)
          .where("LOWER(name) LIKE ?", "%#{downcased}%")
          .first
    end
  end

  def seconds_until(time)
    return 0 if time.nil?
    t = time.is_a?(Time) ? time : (Time.parse(time.to_s) rescue nil)
    return 0 if t.nil?
    secs = (t - Time.now).to_i
    secs > 0 ? secs : 0
  end

  def save_player
    @player.save
  end

  def hit(text)
    text = text.strip
    print "Hit who or what?" and return if text == ""

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
    @client.print "\e[2K\r" # erase current line
    print_hold "You say, \"#{$pastel.cyan(text)}\"."

    World::Manager.room_event(Event.new({
                                          action: ACTION_SAY,
                                          room: self.room,
                                          data: { sender_name: @player.name, text: text },
                                          player: @player,
                                          sender_type: SENDER_TYPE_PLAYER
                                        }))

    hint = World::QuestProgression.new(@player).say_hint(room_id: @room&.id, text: text)
    print "\n(#{hint})" if hint.present?

    check_for_quest_objective({
        objective_type: "say",
        command_text: text
    })
  end

  def list_shop_items
    shop = shop_in_room
    if shop.nil?
      print "There is no shop here."
      return
    end

    items = ShopInventory.where(shop_id: shop.id).includes(:game_object)
    if items.empty?
      print "The shelves are empty."
      return
    end

    print "Items for sale:"
    items.each do |entry|
      obj = entry.game_object
      next if obj.nil?

      stock = entry.stock.to_i
      next if stock <= 0

      print "* #{obj.name} - #{entry.price} credits (#{stock} in stock)"
    end
  end

  def buy_item(text)
    if text.strip == ""
      print "Buy what?"
      return
    end

    shop = shop_in_room
    if shop.nil?
      print "There is no shop here."
      return
    end

    entry = find_shop_item(shop, text)
    if entry.nil?
      print "That item isn't for sale here."
      return
    end

    if entry.stock.to_i <= 0
      print "That item is out of stock."
      return
    end

    price = entry.price.to_i
    if @player.credits.to_i < price
      print "You don't have enough credits."
      return
    end

    obj = entry.game_object
    if obj.nil?
      print "That item isn't available."
      return
    end

    @player.update!(credits: @player.credits.to_i - price)
    entry.update!(stock: entry.stock.to_i - 1)
    add_item_to_player(obj.id, 1)
    print "You buy #{obj.name}."

    emit_room_literal(@player.room_id, "#{@player.name} buys #{obj.name}.")
  end

  def emit_room_literal(room_id, message)
    return if room_id.nil?
    room = Room.find_by(id: room_id)
    return if room.nil?

    World::Manager.room_event(Event.new({
                                          action: ACTION_LITERAL,
                                          room: room,
                                          message: message,
                                          data: { room_id: room_id },
                                          sender_type: SENDER_TYPE_ROOM
                                        }))
  end

  def sell_item(text)
    if text.strip == ""
      print "Sell what?"
      return
    end

    shop = shop_in_room
    if shop.nil?
      print "There is no shop here."
      return
    end

    item = find_player_item(text)
    if item.nil?
      print "You aren't carrying that."
      return
    end

    obj = item.game_object
    if obj.nil?
      print "That item cannot be sold."
      return
    end

    credits = obj.sell_price.to_i
    if credits <= 0
      print "That item isn't worth anything."
      return
    end

    deduct_player_item(item, 1)
    @player.update!(credits: @player.credits.to_i + credits)
    restock_shop_item(shop, obj.id)
    print "You sell #{obj.name}."

    emit_room_literal(@player.room_id, "#{@player.name} sells #{obj.name}.")
  end

  def shop_in_room
    return nil unless @room.room_type_id.to_i == 1

    Shop.find_by(room_id: @room.id)
  end

  def find_shop_item(shop, name)
    items = ShopInventory.where(shop_id: shop.id).includes(:game_object)
    items.find do |entry|
      obj = entry.game_object
      obj.present? && obj.name.downcase.include?(name.downcase)
    end
  end

  def add_item_to_player(object_id, quantity)
    existing = InventoryItem.where(
      owner_type: "PlayerCharacter",
      owner_id: @player.id,
      object_id: object_id
    ).first

    if existing.present?
      existing.update!(quantity: existing.quantity.to_i + quantity)
    else
      InventoryItem.create!(
        owner_type: "PlayerCharacter",
        owner_id: @player.id,
        object_id: object_id,
        quantity: quantity
      )
    end
  end

  def deduct_player_item(item, quantity)
    remaining = item.quantity.to_i - quantity
    if remaining > 0
      item.update!(quantity: remaining)
    else
      item.destroy
    end
  end

  def restock_shop_item(shop, object_id)
    entry = ShopInventory.find_or_initialize_by(shop_id: shop.id, object_id: object_id)
    entry.stock = entry.stock.to_i + 1
    entry.save!
  end

  def wield_item(text)
    if text.strip == ""
      print "Wield what?"
      return
    end

    item = find_player_item(text)
    if item.nil?
      print "You aren't carrying that."
      return
    end

    obj = item.game_object
    if obj.nil? or obj.item_type != "weapon"
      print "You can't wield that."
      return
    end

    required_level = obj.required_level.to_i
    if required_level > 0 && @player.level.to_i < required_level
      print "You are not experienced enough to wield that."
      return
    end

    equip_item("weapon", obj)
    print "You wield the #{obj.name}."
  end

  def unwield_item
    entry = PlayerEquipment.find_by(player_character_id: @player.id, slot: "weapon")
    if entry.nil?
      print "You aren't wielding a weapon."
      return
    end

    entry.destroy
    print "You lower your weapon."
  end

  def wear_item(text)
    if text.strip == ""
      print "Wear what?"
      return
    end

    item = find_player_item(text)
    if item.nil?
      print "You aren't carrying that."
      return
    end

    obj = item.game_object
    if obj.nil? or obj.item_type != "armor"
      print "You can't wear that."
      return
    end

    if obj.slot.present? and obj.slot != "torso"
      print "You can't wear that on your torso."
      return
    end

    required_level = obj.required_level.to_i
    if required_level > 0 and @player.level.to_i < required_level
      print "You are not experienced enough to wear that."
      return
    end

    equip_item("torso", obj)
    print "You wear the #{obj.name}."
  end

  def remove_item(_text)
    entry = PlayerEquipment.find_by(player_character_id: @player.id, slot: "torso")
    if entry.nil?
      print "You aren't wearing any torso armor."
      return
    end

    entry.destroy
    print "You remove your torso armor."
  end

  def equip_item(slot, obj)
    entry = PlayerEquipment.find_or_initialize_by(player_character_id: @player.id, slot: slot)
    entry.object_id = obj.id
    entry.save!
  end

  def find_player_item(name)
    items = InventoryItem.where(owner_type: "PlayerCharacter", owner_id: @player.id).includes(:game_object)
    items.find do |item|
      obj = item.game_object
      obj.present? && obj.name.downcase.include?(name.downcase)
    end
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

  def follow(text)
    if text.strip == ""
      print "Follow whom?"
      return
    end

    entity = find_entity_in_room(text)
    if entity.present?
      case entity[:type]
      when :npc
        npc = entity[:entity]

        if npc.nil?
          print "#{vanna(text)} isn't here."
          return
        elsif npc.followable == false
          print "#{npc.npc_name} cannot be followed."
          return
        elsif @player.following_npc_id != nil
          print "You are already following #{npc.npc_name}. Type 'unfollow' to stop following."
          return
        else
          @player.update!(following_npc_id: npc.id, following_player_id: nil)
          print "You are now following #{npc.npc_name}. Type 'unfollow' to stop following."
          return
        end
      end
    end

    player = Player.where(room_id: @room.id).where("name ILIKE ?", "%#{text.strip}%").first
    if player.nil?
      print "#{vanna(text)} isn't here."
      return
    elsif @player.following_player_id != nil
      print "You are already following #{player.name}. Type 'unfollow' to stop following."
      return
    else
      @player.update!(following_player_id: player.id, following_npc_id: nil)
      print "You are now following #{player.name}. Type 'unfollow' to stop following."
      emit_room_literal(@room.id, "#{@player.name} is now following #{player.name}.")
      return
    end
  end

  def unfollow
    if @player.following_npc_id == nil and @player.following_player_id == nil
      print "You are not following anyone."
      return
    end

    @player.update!(following_npc_id: nil, following_player_id: nil)
    print "You stop following."
    emit_room_literal(@room.id, "#{@player.name} stops following someone.")
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
    print "You search the corpse.\n"
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
    if inventory_item.nil? or inventory_item[:type] != :object
      print "There isn't #{vanna(text)} here."
      return
    end

    take_room_item(inventory_item[:entity])
  end

  def drop_item(text)
    if text.strip == ""
      print "Drop what?"
      return
    end

    item = find_player_item(text)
    if item.nil?
      print "You aren't carrying that."
      return
    end

    obj = item.game_object
    if obj.nil?
      print "You can't drop that."
      return
    end

    drop_inventory_item(item, "Room", @room.id)
    print "You drop #{obj.name}."

    room_npcs = @room.respond_to?(:npc) ? @room.npc : []
    room_npcs.each do |npc|
      result = World::QuestProgression.new(@player).handle_deliver(
        npc_id: npc.id,
        room_id: @room.id,
        item: obj
      )

      next unless result[:updates].to_i > 0

      print $pastel.green("Journal updated.")
      if result[:consume_item]
        dropped_item = InventoryItem.where(
          owner_type: "Room",
          owner_id: @room.id,
          object_id: obj.id
        ).order(:id).first
        dropped_item&.destroy
      end
      break
    end
  end

  def give_item(text)
    if text.strip == ""
      print "Give what to whom?"
      return
    end

    match = text.match(/\A(.+?)\s+to\s+(.+)\z/i)
    if match
      item_name = match[1]
      npc_name = match[2]
    else
      parts = text.split(" ")
      if parts.size < 2
        print "Give what to whom?"
        return
      end
      item_name = parts[0..-2].join(" ")
      npc_name = parts[-1]
    end

    entity = find_entity_in_room(npc_name)
    if entity.nil? || entity[:type] != :npc
      print "#{vanna(npc_name)} isn't here."
      return
    end

    npc = entity[:entity]
    item = find_player_item(item_name)
    if item.nil?
      print "You aren't carrying that."
      return
    end

    obj = item.game_object
    if obj.nil?
      print "#{npc.npc_name} doesn't want that."
      return
    end

    result = World::QuestProgression.new(@player).handle_deliver(
      npc_id: npc.id,
      room_id: @room.id,
      item: obj
    )

    if result[:updates].to_i > 0
      print $pastel.green("Journal updated.")
      deduct_player_item(item, 1) if result[:consume_item]
    else
      deduct_player_item(item, 1)
    end

    print "You give #{obj.name} to #{npc.npc_name}."
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

  def create_llm_quest
    # Create a prompt that can be copied/pasted to ChatGPT to generate quests
    rooms = Room.where(zone_id: @room.zone_id)
    room_list = rooms.map do |r|
      {
        room_id: r.id,
        name: r.name,
        inside_or_outside: r.inside ? "inside" : "outside",
        x: r.x,
        y: r.y,
        z: r.z,
        description: r.description
      }
    end

    mobs = CreatureInstance.joins(:creature)
                           .where(zone_id: @room.zone_id)
                           .map do |ci|
      {
        id: ci.id,
        name: ci.creature_name,
        description: ci.creature.description,
        hp_max: ci.creature.hitmax,
        strength: ci.creature.strength,
        room_id: ci.room_id
      }
    end

    npcs = NPC.where(zone_id: @room.zone_id).map do |npc|
      {
        creature_id: npc.creature.id,
        name: npc.npc_name,
        description: npc.description,
        room_id: npc.room_id,
        can_roam_in_zone: npc.can_roam
      }
    end

    # Load `QUESTS.md` from the project root for additional context
    quest_details = File.read(File.join(File.dirname(__FILE__), '..', 'QUESTS.md'))

    quest_id = Quest.maximum(:id).to_i + 1

    # Build prompt payload for the LLM
    payload = {
      zone: {
        zone_id: @room.zone_id,
        zone_name: @room.zone.name,
        zone_description: @room.zone.description,
        rooms: room_list
      },
      mobs: mobs,
      npcs: npcs,
      quest_implementation_details: quest_details,
      instructions: [
        "Return an array of quest objects that match the 'quests' table columns. The `quest_id` to use for each supporting table is `quest_id=#{quest_id}`.",
        "Each quest object must include keys for the columns listed in the schema (use null or reasonable defaults when appropriate).",
        "Where a column refers to a room (by id), use IDs from the provided rooms list. NEVER mention room IDs in any player-readable text! Refer to rooms by their room name only.",
      ].join(" ")
    }

    prompt_text = <<~PROMPT
      You are an expert game designer tasked with creating quests for a text-based multiplayer game.
      Use the following information to generate quests that fit well within the provided zone.

      ZONE ROOMS:
      #{JSON.pretty_generate(payload[:zone])}

      ZONE MOBS:
      In the database, mobs are `creature_instances` linked to `creatures`. If a quest requires killing a mob enemy, be sure that the enemy exists in the room_id you're referencing!
      #{payload[:mobs]}
      
      ZONE NPCS:
      Note: some NPCs can roam the zone, others never leave the room they're placed in.
      #{payload[:npcs]}

      INSTRUCTIONS:
      #{payload[:instructions]}

      QUEST IMPLEMENTATION DETAILS:
      #{payload[:quest_implementation_details]}

      OUTPUT:
      Provide a list of SQL INSERT statements to create the quests in the database. When the quest is inserted in the `quests` table, the new quest_id will be `#{quest_id}` so use that for all supporting tables.
    PROMPT

    print prompt_text
  end

  def get_table_schema(table_name)
    conn = ActiveRecord::Base.connection

    # Columns
    columns = conn.columns(table_name).map do |c|
      {
        name: c.name,
        rails_type: c.type,    # symbol like :integer, :string, etc.
        sql_type: c.sql_type,  # raw SQL type
        default: c.default,
        null: c.null,
        limit: c.limit
      }
    end

    # Foreign keys
    foreign_keys = if conn.respond_to?(:foreign_keys)
                     conn.foreign_keys(table_name).map do |fk|
                       {
                         from_table: fk.from_table,
                         to_table: fk.to_table,
                         column: (fk.options[:column] || fk.column),
                         primary_key: (fk.options[:primary_key] || fk.primary_key)
                       }
                     end
                   else
                     []
                   end

    {
      table: table_name,
      columns: columns,
      foreign_keys: foreign_keys
    }
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
    check_for_quest_objective({
      objective_type: "collect",
      target_type: "object",
      object: obj
    })
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
