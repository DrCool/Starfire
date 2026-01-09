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
      when "jobs"
        if text.to_s.strip == ""
          list_jobs
        else
          show_job_details(text)
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
    when "exa", "examine"
    		entity = find_entity_in_room(text)
        if entity.present?
          prop = entity[:type] == :prop ? entity[:entity] : nil
          check_for_quest_objective("examine", text, prop: prop)
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
	end

	def who
		who = User.get_logged_in_users
		who = who.pluck(:name)
		print "CURRENTLY ONLINE:"
		print "* " + who.join("\n\r* ")
	end

  # List jobs/quests at the current board
  def list_jobs
    unless @room.room_type_id.to_i == 5
      print "There is no quest board here."
      return
    end

    level = @player.level.to_i

    quests = Quest
      .where(is_active: 1, start_room_id: @room.id)
      .where("min_level IS NULL OR min_level <= ?", level)
      .where("max_level IS NULL OR max_level >= ?", level)
      .order(Arel.sql("COALESCE(min_level, 0) ASC"))
      .order(:id)
      .to_a

    # Apply prerequisites if the table exists.
    if quests_table_exists?("quest_prerequisites")
      quests = quests.select { |q| prerequisites_pass?(q.id) }
    end

    print ""
    print $pastel.on_red($pastel.bright_white($pastel.bold("                         ")))
    print $pastel.on_red($pastel.bright_white($pastel.bold("       Quest Board       ")))
    print $pastel.on_red($pastel.bright_white($pastel.bold("                         ")))
    print ""

    if quests.empty?
      print "No quests are posted here."
      return
    end

    now = Time.now

    quests.each do |q|
      quest_id = q.id.to_i
      name = (q.name.presence || q.quest_key.to_s)
      summary = q.summary.to_s
      repeatable = q.repeatable?

      cq = nil
      if quests_table_exists?("character_quests")
        cq = fetch_latest_character_quest(@player.id, quest_id)
      end

      status = "AVAILABLE"
      cooldown_note = nil

      if cq.present?
        state = cq.state.to_s
        cooldown_until = cq.cooldown_until

        cooldown_time = nil
        if cooldown_until.present?
          cooldown_time = cooldown_until.is_a?(Time) ? cooldown_until : Time.parse(cooldown_until.to_s) rescue nil
        end

        if state == "active"
          status = "ACTIVE"
        elsif state == "completed" && !repeatable
          status = "COMPLETED"
        elsif repeatable
          if cooldown_time && cooldown_time > now
            status = "COOLDOWN"
            secs = (cooldown_time - now).to_i
            cooldown_note = "(#{secs}s)"
          else
            status = "AVAILABLE"
          end
        elsif state == "abandoned"
          if cooldown_time && cooldown_time > now
            status = "COOLDOWN"
            secs = (cooldown_time - now).to_i
            cooldown_note = "(#{secs}s)"
          else
            status = "AVAILABLE"
          end
        end
      end

      header = "#{quest_id}) #{name} [#{status}]"
      header += " #{cooldown_note}" if cooldown_note.present?
      print header

      print "   #{summary}" if summary.present?

      rewards = fetch_quest_rewards_summary(quest_id)
      print "   Reward: #{rewards}" if rewards.present?

      print "   Type: accept #{quest_id}"
    end
  end

  def show_job_details(text)
    unless @room.room_type_id.to_i == 5
      print "There is no quest board here."
      return
    end

    token = text.to_s.strip.split(" ").first
    unless token.present? && token =~ /^\d+$/
      print "Usage: jobs <quest_id>"
      return
    end

    quest_id = token.to_i

    q = Quest.find_by(id: quest_id, is_active: 1, start_room_id: @room.id)
    if q.nil?
      print "That quest is not posted here."
      return
    end

    print ""
    print "#{q.id}) #{q.name.presence || q.quest_key}"

    if q.summary.present?
      print q.summary.to_s
    end

    min_lvl = q.respond_to?(:min_level) ? q.min_level : nil
    max_lvl = q.respond_to?(:max_level) ? q.max_level : nil

    if min_lvl.present? || max_lvl.present?
      req = []
      req << "min #{min_lvl}" if min_lvl.present?
      req << "max #{max_lvl}" if max_lvl.present?
      print "Level: #{req.join(", ") }"
    end

    repeatable = q.repeatable?
    cooldown_seconds = q.respond_to?(:cooldown_seconds) ? q.cooldown_seconds.to_i : 0

    if repeatable
      if cooldown_seconds > 0
        print "Repeatable: yes (cooldown #{cooldown_seconds}s)"
      else
        print "Repeatable: yes"
      end
    else
      print "Repeatable: no"
    end

    rewards = fetch_quest_rewards_summary(q.id)
    print "Reward: #{rewards}" if rewards.present?

    if quests_table_exists?("quest_steps")
      steps = ActiveRecord::Base.connection.exec_query(
        "SELECT step_number, name, description FROM quest_steps WHERE quest_id = #{ActiveRecord::Base.connection.quote(q.id)} ORDER BY step_number ASC"
      ).to_a

      if steps.any?
        print ""
        print "Steps:"
        steps.each do |s|
          step_no = s["step_number"].to_i
          step_name = s["name"].to_s
          step_desc = s["description"].to_s
          print "Step #{step_no}: #{step_name}".strip
          print "   #{step_desc}" if step_desc.present?
        end
      end
    end

    print ""
    print "Type: accept #{q.id}"
    print "Once complete, return here and type: complete #{q.id}"
  end

  def accept_quest(text)
    unless @room.room_type_id.to_i == 5
      print "You need to be at a job board to accept quests."
      return
    end

    token = text.to_s.strip.split(" ").first
    unless token.present? && token =~ /^\d+$/
      print "Usage: accept <quest_id>"
      return
    end

    quest_id = token.to_i

    q = Quest.find_by(id: quest_id, is_active: 1, start_room_id: @room.id)
    if q.nil?
      print "That quest is not posted here."
      return
    end

    level = @player.level.to_i
    min_lvl = q.respond_to?(:min_level) ? q.min_level : nil
    max_lvl = q.respond_to?(:max_level) ? q.max_level : nil

    if min_lvl.present? && level < min_lvl.to_i
      print "You are not experienced enough for that quest."
      return
    end

    if max_lvl.present? && level > max_lvl.to_i
      print "That quest is meant for less experienced players."
      return
    end

    if quests_table_exists?("quest_prerequisites")
      unless prerequisites_pass?(q.id)
        print "You do not meet the prerequisites for that quest."
        return
      end
    end

    repeatable = q.repeatable?
    cq = fetch_latest_character_quest(@player.id, q.id) if quests_table_exists?("character_quests")

    if cq.present?
      state = cq.state.to_s
      if state == "active"
        print "You have already accepted that quest."
        return
      end

      if state == "completed" && !repeatable
        print "You have already completed that quest."
        return
      end

      if repeatable
        secs = seconds_until(cq.cooldown_until)
        if secs > 0
          print "That quest is not available yet. Check back in #{secs}s."
          return
        end
      end
    end

    fk = character_quest_fk_column

    attrs = {
      fk => @player.id,
      quest_id: q.id,
      state: "active"
    }

    attrs[:current_step_number] = 1 if CharacterQuest.column_names.include?("current_step_number")
    attrs[:started_at] = Time.now if CharacterQuest.column_names.include?("started_at")

    new_cq = CharacterQuest.create!(attrs)

    QuestObjective.where(quest_id: q.id).find_each do |obj|
      oattrs = {
        character_quest_id: new_cq.id,
        quest_objective_id: obj.id
      }
      oattrs[:current_count] = 0 if CharacterQuestObjective.column_names.include?("current_count")
      oattrs[:is_completed] = 0 if CharacterQuestObjective.column_names.include?("is_completed")
      oattrs[:is_complete] = 0 if CharacterQuestObjective.column_names.include?("is_complete")
      CharacterQuestObjective.create!(oattrs)
    end

    print "You accept: #{q.name.presence || q.quest_key}"
    print "Type 'journal' to track your active quests."
  rescue => e
    print "Could not accept that quest."
    print "Error: #{e.message}"
  end

  def complete_quest(text)
    token = text.to_s.strip.split(" ").first
    unless token.present? && token =~ /^\d+$/
      print "Usage: complete <quest_id>"
      return
    end

    quest_id = token.to_i

    cq = active_character_quests.find { |row| row.quest_id.to_i == quest_id }
    if cq.nil?
      print "You do not have that quest active."
      return
    end

    q = Quest.find_by(id: quest_id)
    quest_name = q&.name.presence || q&.quest_key.to_s || "Quest #{quest_id}"

    step = current_step_for(cq)
    if step.nil?
      print "That quest cannot be turned in right now."
      return
    end

    objectives = QuestObjective.where(
      quest_id: quest_id,
      step_id: step.id,
      objective_type: "turnin"
    ).to_a

    if objectives.empty?
      print "That quest cannot be turned in right now."
      return
    end

    turnin = objectives.any? do |obj|
      target_room = obj.target_room_id.to_i if obj.respond_to?(:target_room_id)
      next true if target_room.nil? || target_room == 0
      target_room == @room.id
    end

    unless turnin
      print "You need to be at the turn-in location to complete that quest."
      return
    end

    progress = World::QuestProgression.new(@player)
    updates = progress.handle_turn_in(quest_id: quest_id, room_id: @room.id)

    if updates <= 0
      print "You are not ready to complete that quest."
      return
    end

    cq.reload

    if cq.state.to_s == "completed"
      print $pastel.green("Quest completed: #{quest_name}")
      rewards = fetch_quest_rewards_summary(quest_id)
      print "Reward: #{rewards}" if rewards.present?
    else
      print "Quest updated: #{quest_name}"
    end
  rescue => e
    print "Could not complete that quest."
    print "Error: #{e.message}"
  end

  def check_for_quest_objective(action, text, context = {})
    return if action.to_s.strip.empty?
    return unless defined?(World::QuestProgression)
    return unless quests_table_exists?("character_quests")
    return unless quests_table_exists?("quest_objectives")

    case action.to_s
    when "examine"
      prop = context[:prop] || resolve_prop_in_room(text)
      return if prop.nil?

      progress = World::QuestProgression.new(@player)
      updates = progress.handle_examine(target: prop, room_id: @room&.id)
      print $pastel.green("Journal updated.") if updates.to_i > 0
    end
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

  def journal(text)
    args = text.to_s.strip.split(" ")

    # Abandon flow: journal abandon <quest_id>
    if args.first.to_s.downcase == "abandon"
      token = args[1]
      unless token.present? && token =~ /^\d+$/
        print "Usage: journal abandon <quest_id>"
        return
      end

      quest_id = token.to_i
      cq = active_character_quests.find { |row| row.quest_id.to_i == quest_id }

      if cq.nil?
        print "You do not have that quest active."
        return
      end

      q = Quest.find_by(id: quest_id)
      quest_name = q&.name.presence || q&.quest_key.to_s || "Quest #{quest_id}"

      cq.state = "abandoned" if cq.respond_to?(:state=)
      cq.abandoned_at = Time.now if cq.respond_to?(:abandoned_at=) && CharacterQuest.column_names.include?("abandoned_at")

      cooldown_seconds = 0
      if q && q.respond_to?(:cooldown_seconds)
        cooldown_seconds = q.cooldown_seconds.to_i
      end

      if q && q.respond_to?(:repeatable?) && q.repeatable? && cooldown_seconds > 0 && cq.respond_to?(:cooldown_until=) && CharacterQuest.column_names.include?("cooldown_until")
        cq.cooldown_until = Time.now + cooldown_seconds
      end

      cq.save!

      print "You abandon: #{quest_name}"

      secs = seconds_until(cq.respond_to?(:cooldown_until) ? cq.cooldown_until : nil)
      print "You can accept it again in #{secs}s." if secs > 0
      return
    end

    # List flow: journal
    if args.empty? || args.first.to_s.strip == ""
      cqs = active_character_quests
      if cqs.empty?
        print "Your journal is empty."
        return
      end

      quest_ids = cqs.map { |row| row.quest_id.to_i }.uniq
      quests_by_id = Quest.where(id: quest_ids).to_a.each_with_object({}) { |qq, h| h[qq.id.to_i] = qq }

      print ""
      print $pastel.on_blue($pastel.bright_white($pastel.bold("                         ")))
      print $pastel.on_blue($pastel.bright_white($pastel.bold("         Journal         ")))
      print $pastel.on_blue($pastel.bright_white($pastel.bold("                         ")))
      print ""

      cqs.each do |cq|
        q = quests_by_id[cq.quest_id.to_i]
        name = q&.name.presence || q&.quest_key.to_s || "Quest #{cq.quest_id}"
        qid = cq.quest_id.to_i
        print "#{$pastel.cyan(qid.to_s)}) #{$pastel.bold(name)}"

        step = current_step_for(cq)
        if step
          step_label = "Step #{step.step_number}: #{step.name}".strip
          print "   #{$pastel.yellow(step_label)}"
        end

        if defined?(CharacterQuestObjective) && defined?(QuestObjective) && quests_table_exists?("character_quest_objectives")
          begin
            rows = CharacterQuestObjective.where(character_quest_id: cq.id).to_a
            total = rows.length
            complete = rows.count { |r| objective_completed?(r) }
            if total > 0
              obj_line = "Objectives: #{complete}/#{total}"
              print "   #{$pastel.magenta(obj_line)}"
            end
          rescue
          end
        end

        # Turn-in reminder line
        room = quest_turn_in_room(q)
        if room
          turn = "Turn-in: #{room.name}"
          cmd = "complete #{cq.quest_id}"
          print "   #{$pastel.cyan(turn)} (#{$pastel.yellow(cmd)})"
        else
          cmd = "complete #{cq.quest_id}"
          print "   #{$pastel.cyan('Turn-in:')} #{$pastel.yellow(cmd)}"
        end

        hint = "journal #{cq.quest_id}"
        print "   #{$pastel.bright_black('Details:')} #{$pastel.yellow(hint)}"
      end

      return
    end

    # Detail flow: journal <quest_id>
    token = args.first
    unless token.present? && token =~ /^\d+$/
      print "Usage: journal <quest_id>"
      return
    end

    quest_id = token.to_i

    cq = active_character_quests.find { |row| row.quest_id.to_i == quest_id }
    if cq.nil?
      print "You do not have that job active."
      return
    end

    q = Quest.find_by(id: quest_id)
    name = q&.name.presence || q&.quest_key.to_s || "Quest #{quest_id}"

    print ""
    print "#{$pastel.cyan(quest_id.to_s)}) #{$pastel.bold(name)} #{$pastel.green('[ACTIVE]')}"
    print q.summary.to_s if q&.respond_to?(:summary) && q.summary.present?

    step = current_step_for(cq)
    if step
      print ""
      step_line = "Current Step #{step.step_number}: #{step.name}".strip
      print $pastel.yellow(step_line)
      print "   #{step.description}" if step.respond_to?(:description) && step.description.present?
    end

    if defined?(CharacterQuestObjective) && defined?(QuestObjective) && quests_table_exists?("character_quest_objectives")
      begin
        rows = CharacterQuestObjective.where(character_quest_id: cq.id).to_a
        if rows.any?
          obj_ids = rows.map { |r| r.quest_objective_id.to_i }.uniq
          objs_by_id = QuestObjective.where(id: obj_ids).to_a.each_with_object({}) { |oo, h| h[oo.id.to_i] = oo }

          print ""
          print $pastel.magenta($pastel.bold("Objectives:"))
          rows.each do |r|
            obj = objs_by_id[r.quest_objective_id.to_i]
            label = obj&.description.presence || obj&.objective_type.to_s || "Objective #{r.quest_objective_id}"

            # Progress formatting
            cur = r.respond_to?(:current_count) ? r.current_count.to_i : nil
            tgt = obj&.respond_to?(:required_count) ? obj.required_count.to_i : nil
            done = objective_completed?(r)

            done_tag = done ? " #{$pastel.green('[DONE]')}" : ""

            if cur && tgt && tgt > 0
              prog = "(#{cur}/#{tgt})"
              print "- #{label} #{$pastel.yellow(prog)}#{done_tag}"
            else
              print "- #{label}#{done_tag}"
            end
          end
        end
      rescue
      end
    end

    print ""
    # Turn-in reminder for detail view
    room = quest_turn_in_room(q)
    if room
      turn = "Turn-in: #{room.name}"
      cmd = "complete #{quest_id}"
      print "#{$pastel.cyan(turn)} (#{$pastel.yellow(cmd)})"
    else
      cmd = "complete #{quest_id}"
      print "#{$pastel.cyan('Turn-in:')} #{$pastel.yellow(cmd)}"
    end

    abandon_cmd = "journal abandon #{quest_id}"
    print "#{$pastel.bright_black('Abandon:')} #{$pastel.yellow(abandon_cmd)}"
  end

  def active_character_quests
    return [] unless defined?(CharacterQuest)
    return [] unless quests_table_exists?("character_quests")

    fk = character_quest_fk_column

    CharacterQuest
      .where(fk => @player.id, state: "active")
      .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
      .order(id: :desc)
      .to_a
  rescue
    []
  end

  def objective_completion_column
    return "is_completed" if defined?(CharacterQuestObjective) &&
      CharacterQuestObjective.column_names.include?("is_completed")
    return "is_complete" if defined?(CharacterQuestObjective) &&
      CharacterQuestObjective.column_names.include?("is_complete")

    nil
  end

  def objective_completed?(row)
    col = objective_completion_column
    return false if col.nil?

    return false unless row.respond_to?(col)

    value = row.send(col)
    return true if value == true
    return false if value == false || value.nil?

    value.to_i == 1
  end

  def current_step_for(character_quest)
    return nil unless defined?(QuestStep)
    return nil unless quests_table_exists?("quest_steps")

    step_no = 1
    if character_quest.respond_to?(:current_step_number) && character_quest.current_step_number.present?
      step_no = character_quest.current_step_number.to_i
    end

    QuestStep.find_by(quest_id: character_quest.quest_id, step_number: step_no) ||
      QuestStep.where(quest_id: character_quest.quest_id).order(:step_number).first
  rescue
    nil
  end

  # Helper to fetch the quest turn-in room safely
  def quest_turn_in_room(quest)
    return nil if quest.nil?
    return nil unless quest.respond_to?(:start_room_id)
    rid = quest.start_room_id
    return nil if rid.nil?
    Room.find_by(id: rid)
  rescue
    nil
  end

  def seconds_until(time)
    return 0 if time.nil?
    t = time.is_a?(Time) ? time : (Time.parse(time.to_s) rescue nil)
    return 0 if t.nil?
    secs = (t - Time.now).to_i
    secs > 0 ? secs : 0
  end

  def quests_table_exists?(table_name)
    ActiveRecord::Base.connection.data_source_exists?(table_name)
  rescue
    false
  end

  def character_quest_fk_column
    return :player_character_id if defined?(CharacterQuest) && CharacterQuest.column_names.include?("player_character_id")
    return :character_id if defined?(CharacterQuest) && CharacterQuest.column_names.include?("character_id")
    # Fallback to the association name if neither column is present.
    :player_character_id
  end

  def fetch_latest_character_quest(character_id, quest_id)
    return nil unless defined?(CharacterQuest)

    fk = character_quest_fk_column

    CharacterQuest
      .where(fk => character_id, quest_id: quest_id)
      .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
      .order(id: :desc)
      .first
  rescue
    nil
  end

  def prerequisites_pass?(quest_id)
    # If prerequisites tables aren't present, allow.
    return true unless quests_table_exists?("quest_prerequisites")

    prereqs = ActiveRecord::Base.connection.exec_query(
      "SELECT prereq_type, prereq_key, prereq_value FROM quest_prerequisites WHERE quest_id = #{ActiveRecord::Base.connection.quote(quest_id)}"
    ).to_a

    return true if prereqs.empty?

    level = @player.level.to_i

    prereqs.all? do |p|
      case p["prereq_type"].to_s
      when "level"
        level >= p["prereq_value"].to_i
      when "quest_completed"
        next true unless quests_table_exists?("character_quests")
        req_quest_id = p["prereq_value"].to_i
        row = ActiveRecord::Base.connection.select_one(
          "SELECT id FROM character_quests WHERE character_id = #{ActiveRecord::Base.connection.quote(@player.id)} AND quest_id = #{ActiveRecord::Base.connection.quote(req_quest_id)} AND state = 'completed' LIMIT 1"
        )
        row.present?
      when "flag"
        next true unless quests_table_exists?("character_flags")
        key = p["prereq_key"].to_s
        val = p["prereq_value"]
        if val.nil?
          row = ActiveRecord::Base.connection.select_one(
            "SELECT id FROM character_flags WHERE character_id = #{ActiveRecord::Base.connection.quote(@player.id)} AND flag_key = #{ActiveRecord::Base.connection.quote(key)} LIMIT 1"
          )
        else
          row = ActiveRecord::Base.connection.select_one(
            "SELECT id FROM character_flags WHERE character_id = #{ActiveRecord::Base.connection.quote(@player.id)} AND flag_key = #{ActiveRecord::Base.connection.quote(key)} AND flag_value = #{ActiveRecord::Base.connection.quote(val.to_s)} LIMIT 1"
          )
        end
        row.present?
      else
        # Unknown prereq type: be permissive.
        true
      end
    end
  rescue
    true
  end

  def fetch_quest_rewards_summary(quest_id)
    if defined?(QuestReward)
      rows = QuestReward.where(quest_id: quest_id).to_a
      return nil if rows.empty?

      credits = rows.select { |r| r.reward_type.to_s == "credits" }.sum { |r| r.amount.to_i }
      xp = rows.select { |r| r.reward_type.to_s == "xp" }.sum { |r| r.amount.to_i }

      parts = []
      parts << "#{credits} credits" if credits > 0
      parts << "#{xp} xp" if xp > 0

      return parts.any? ? parts.join(", ") : nil
    end

    return nil unless quests_table_exists?("quest_rewards")

    rows = ActiveRecord::Base.connection.exec_query(
      "SELECT reward_type, amount FROM quest_rewards WHERE quest_id = #{ActiveRecord::Base.connection.quote(quest_id)}"
    ).to_a

    return nil if rows.empty?

    credits = rows.select { |r| r["reward_type"].to_s == "credits" }.sum { |r| r["amount"].to_i }
    xp = rows.select { |r| r["reward_type"].to_s == "xp" }.sum { |r| r["amount"].to_i }

    parts = []
    parts << "#{credits} credits" if credits > 0
    parts << "#{xp} xp" if xp > 0

    parts.any? ? parts.join(", ") : nil
  rescue
    nil
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
      action: ACTION_SAY,
      room: self.room,
      data: { sender_name: @player.name, text: text },
      player: @player,
      sender_type: SENDER_TYPE_PLAYER
    }))
    @client.print "\e[2K\r" # erase current line
    print_hold "You say, \"#{$pastel.cyan(text)}\"."
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
