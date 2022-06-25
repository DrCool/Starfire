# encoding: utf-8
require '../model/user'
require '../model/player_character'
require '../model/room'
require '../model/room_saying'
require '../model/npc'
require '../model/npc_movement'
require '../model/npc_saying'
require '../model/prop'
require '../model/creature'
require '../model/custom_command'
require '../model/creature_instance'
require 'world'

require 'pastel'
require 'bcrypt'
require 'game_commands'
require 'workers'
require 'tribe'
require 'activerecord-import'

# perl-like text string formatting gem
# https://www.rubydoc.info/gems/formatr/1.10.1/FormatR


class Lands
  include BCrypt
  include GameCommands
  include World
  attr_accessor :client, :player, :room, :command, :dir_list, :lands_instance
  @pause_events = false

  def overprint(text)
    @client.print "\e[2K\r" # erase current line
    print text
    show_prompt
    @client.print @input
  end
  def self.overprint(text)
    @client.print "\e[2K\r" # erase current line
    self.print text
    self.show_prompt
    @client.print @input
  end

  def initialize
    connect_db

    @client = nil
    @input = ""
    @room = nil
    @command = ""
    @command_history = []
    @cmd_history_index = 0
    @overprint = lambda do |text|
      @client.print "\e[2K\r" # erase current line
      print text
      show_prompt
      @client.print @input
    end
  end

  def connect_db
    config = {
      adapter: 'mysql2',
      host: 'localhost',
      username: 'root',
      password: '',
      database: 'lands_game',
      reconnect: true,
      pool: 100
    }

    #ActiveRecord::Base.connection_pool.disconnect!
    #ActiveSupport.on_load(:active_record) do
    #  ActiveRecord::Base.establish_connection(config) # Establish connection is not needed for Rails 5.2+ https://github.com/rails/rails/pull/31241
    #end
  end

  def start_game(client)
    @client = client
    show_cursor
    title_screen
    @user, @player = login
    @player.client = client
#@player = PlayerCharacter.first
    print "Welcome, #{@player.name}!\n"
    Thread.current[:op].set_player(@player)

    # Send IAC DO SGA - IAC WILL SGA (SGA = Suppress Go-Ahead signal)
    print_hold "\xff\xfd\x03\xff\xfb\x03" # the client will send typed characters immediately instead of when the user hits enter
    6.times { @client.getc } # get client response to IAC codes and ignore

    # Send IAC WILL ECHO (client will not display characters typed in terminal, this program will echo their characters back to them instead)
    print_hold "\xff\xfb\x01"
    3.times { @client.getc } # get client response to IAC codes and ignore

    load_room
    World::Manager.room_event(Event.new({
      action: ACTION_ENTER_GAME,
      room: @room,
      message: $pastel.bright_yellow(@player.name) + " entered the game and appeared here.",
      player: @player
    }))

    print_location

    main_loop
  end

  def login
    user = nil
    player = nil
    loop do # loop through login sequence until we have a valid user
      username = get_username
      username = create_new_user if username == "new"
      error, user, player = load_user(username)

      print error if error.present?
      break if user.present?
    end
    #user.client = @client

    puts "#{player.name} logged in."
    [user, player]
  end

  def get_username
    print "\n(type '"+$pastel.bright_green("new")+"' to create a new character)"
    print_hold $pastel.bright_yellow("Username: ")
    get_line(true)
  end

  def load_user(username)
    user = User.find_by_username(username)
    player_character = nil
    if user.present?
      #password = get_password
      #password = password[3..-1]
      #if user.password == password
        user.logged_in = true
        user.last_login_at = user.current_login_at
        user.current_login_at = Time.now
        logins = user.login_count || 0
        user.login_count = logins + 1
        user.save

        player_character = PlayerCharacter.find_by_user_id(user.id)
        player_character.logged_in = true
        player_character.save
      #else
      #  return [ "Incorrect password", nil, nil ]
      #end
    else
      return [ "User not found", nil, nil ]
    end

    return [ nil, user, player_character ]
  end

  def create_new_user
    print "\n\nWelcome, new user!\n";
    print "What do you want your character's name to be?";
    print_hold "\nName: ";
    username = get_line(true)
    print "This will be the name you'll use to login from now on."

    print_hold "\nCreate a password: ";
    print_hold "\xff\xfb\x01" # suppress echo on client to prevent display of password
    pass = Password.create(get_line(true));
    print "\xff\xfc\x01" # re-enable echo on client

    user = User.new
    user.username = username
    user.password = pass
    user.logged_in = true
    user.current_login_at = Time.now
    user.login_count = 1
    user.save

    player_character = PlayerCharacter.new
    player_character.name = username
    player_character.user_id = user.id
    player_character.save

    puts "\033[7m #{name}\e[0m just logged in as a new user.";
    username
  end

  def title_screen
    clear
    print File.open("#{File.dirname(__FILE__)}/login_screen.txt").read
  end

  def print(text)
    return if text.nil?
    begin
      @client.puts(text + "\r")
    rescue IOError
      World::Manager.logout_player(@player)
      Thread.current.exit
    end
  end
  def self.print(text)
    return if text.nil?
    begin
      @client.puts(text + "\r")
    rescue IOError
      World::Manager.logout_player(@player)
      Thread.current.exit
    end
  end



  def print_hold(text)
    return if text.nil?
    begin
      @client.print(text)
    rescue IOError
      World::Manager.logout_player(@player)
      Thread.current.exit
    end
  end
  def self.print_hold(text)
    return if text.nil?
    begin
      @client.print(text)
    rescue IOError
      World::Manager.logout_player(@player)
      Thread.current.exit
    end
  end

  def clear
    print_hold "\033[2J\033[H"
  end

  def get_line(simple_mode = false)
    line = ""
    if simple_mode
      return @client.gets.chomp.strip
    else
      while true
        char = @client.recvfrom(3)
        char = char.first

        if char == "\x7F" && line != ""
          line = line[0...-1]
          erase_client_characters(1)
        end

        if char.ord == 13
          print_hold "\r\n"
          return line
          break
        end

        print_hold char
        line += char if char.ord != 13 and char != "\x00" and char != "\x7F"
      end
    end
  end




  #################################################################################################################
  def get_input
    char = @client.recvfrom(3)
    char = char.first
    char = "" if char == "\r"

    if char == "\x7F" && @input != ""
      @input = @input[0...-1]
      erase_client_characters(1)
    end

    if char.ord== 13 # enter key
      val = @input
      if @input != ""
        @command_history << val
        @cmd_history_index = @command_history.count
      end
      @input = ""
      return val
    end

    if char == "\e[A" # up
      char = ""
      if @cmd_history_index > 0
        # show previous command
        @cmd_history_index -= 1
        @input = @command_history[@cmd_history_index] || ""
        print_hold "\e[M\r"
        show_prompt
        print_hold @input
      end
      return
    elsif char == "\e[B" # down
      char = ""
      if @cmd_history_index < @command_history.count
        # show next command in history
        @cmd_history_index += 1
        @input = @command_history[@cmd_history_index] || ""
        print_hold "\e[M\r"
        show_prompt
        print_hold @input
      end
      return
    elsif char == "\e[C" # right
      char = ""
      return
    elsif char == "\e[D" # left
      char = ""
      return
    end

    print_hold char
    @input += char if char.ord != 13 and char != "\x00" and char != "\x7F"
    nil
  end
  #################################################################################################################

  def erase_client_characters(num)
    num.times { print_hold "\x08" } # backspace
    num.times { print_hold "\x20" } # space
    num.times { print_hold "\x08" } # backspace
  end

  def get_password
    print_hold $pastel.bright_yellow("Password: ");
    print_hold "\xff\xfb\x01" # suppress echo on client to prevent display of password
    password = get_line(true)
    print "\xff\xfc\x01" # re-enable echo on client
    password
  end

#  Value: 25
#  Weight: 3
#  Wieldable: no
#  Wearable: no

  def get_char
    while true
      char = @client.recvfrom(3)
      char = char.first
      return char
    end
  end

  def get_only_cursor_key_input
    while true
      char = @client.recvfrom(3)
      char = char.first

      return KEY.ENTER if char.ord == 13
      return KEY.ESC if char == "\e"
      return KEY.UP if char == "\e[A"
      return KEY.DOWN if char == "\e[B"      
      return KEY.LEFT if char == "\e[D"
      return KEY.RIGHT if char == "\e[C"
    end
  end

  def form(data)
    sel_index = 0
    hide_cursor
    print_form(sel_index, data)

    key = -1
    while key != KEY.ESC
      key = get_char
      key = KEY.ENTER if key.ord == 13
      key = KEY.ESC if key == "\e"
      key = KEY.UP if key == "\e[A"
      key = KEY.DOWN if key == "\e[B"      
      key = KEY.LEFT if key == "\e[D"
      key = KEY.RIGHT if key == "\e[C"
      key = KEY.DELETE if key == "\x7F"
      key = KEY.SPACE if key == " "

      if key == KEY.DOWN
        sel_index += 1
        sel_index = 0 if sel_index >= data.length
      elsif key == KEY.UP
        sel_index -= 1
        sel_index = data.length-1 if sel_index < 0
      elsif key == KEY.ENTER
        if data[sel_index][:type] == FIELD_TYPE_CANCEL
          cancel = true 
        elsif data[sel_index][:type] == FIELD_TYPE_SAVE
          save = true
        else

        end
      elsif key == KEY.ESC
        cancel = true
        break
      elsif key == KEY.DELETE
        field_type = data[sel_index][:type]
        if field_type == FIELD_TYPE_STRING or field_type == FIELD_TYPE_INTEGER
          len = data[sel_index][:value][:existing_value].length
          data[sel_index][:value][:existing_value] = data[sel_index][:value][:existing_value][0...len-1]
        end
      elsif key == KEY.SPACE
        field_type = data[sel_index][:type]
        if field_type == FIELD_TYPE_BOOLEAN
          data[sel_index][:value][:existing_value] = !data[sel_index][:value][:existing_value]
        end

      else # alphanumeric character
        field_type = data[sel_index][:type]
        if field_type == FIELD_TYPE_STRING
          data[sel_index][:value][:existing_value] += key
        elsif field_type == FIELD_TYPE_INTEGER
          data[sel_index][:value][:existing_value] = data[sel_index][:value][:existing_value].to_s + key
        end
      end

      break if cancel or save

      print_hold "\e[#{data.length-2}A\r"
      print_form(sel_index, data)
    end

    clear_block data.length
    show_cursor
  end

  def print_form(sel_index, data)
    data.each_with_index do |item, index|
      field_type = item[:type]

      if [FIELD_TYPE_SAVE, FIELD_TYPE_CANCEL].include? field_type
        if index == sel_index
          print_hold $pastel.black.on_bright_yellow(item[:name]) + "  "
        else
          print_hold $pastel.black.on_green(item[:name]) + "  "
        end
      else
        print_hold item[:name] + "  "
      end

      back_color = :on_bright_yellow
      fore_color = :black
      if index == sel_index
        prefix = ">" + $pastel.decorate(" ", back_color, fore_color)
      else
        prefix = " " + $pastel.decorate(" ", back_color, fore_color)
      end


      if field_type == FIELD_TYPE_BOOLEAN
        value = item[:value][:existing_value].to_s
        print prefix + $pastel.decorate(value+" ", fore_color, back_color)
      elsif field_type == FIELD_TYPE_INTEGER
        value = item[:value][:existing_value]
        value = 0 if value.nil?
        value = value.to_s
        max_chars = item[:value][:max_display_chars]
        value = [0...max_chars-3]+"..." if value.length > max_chars
        value = value + (" " * (max_chars-value.length)) if value.length < max_chars

        print prefix + $pastel.decorate(value+" ", fore_color, back_color)
      elsif field_type == FIELD_TYPE_STRING
        value = item[:value][:existing_value] || ""
        max_chars = item[:value][:max_display_chars]
        value = value[0...max_chars-3]+"..." if value.length > max_chars
        value = value + (" " * (max_chars-value.length)) if value.length < max_chars

        print prefix + $pastel.decorate(value+" ", fore_color, back_color)
      end
    end
  end


  def scrolling_menu(question, options)
    max_width = get_max_array_width(options)

    @room_saying_thread.kill

    print question
    print $pastel.bright_black("Cursor UP/DOWN keys to change, ENTER to select, ESC to cancel")

    draw_box(nil, max_width, options.count)
    #print "\n" + question

    indent = "\e[2C"
    hide_cursor



    # Trim options to no more than max_width characters and pad with spaces
    options = options.map do |opt|
      return_val = opt
      if opt.length > max_width
        return_val = opt[0...max_width-3] + "..."
      end
      remainder = max_width - opt.length
      remainder = 0 if remainder < 0
      return_val = return_val + (" " * remainder)
      return_val
    end

    index = 0
    options.each_with_index do |opt, i|
      if index == i
        print_hold indent + $pastel.black.on_cyan(" " + opt + " ")
      else
        print_hold indent + " " + opt + " "
      end
      if i != options.count-1
        print ""
      end
    end
    print_hold "\e[#{options.count-1}A" # move cursor up to the first line

    while true
      characters = @client.recvfrom(3) # get up to three bytes from input buffer
      # puts characters.inspect
      char = characters.first

      old_index = index
      if char == "\e[A" # UP
        # first, remove the highlighting on this item by reprinting before moving the cursor.
        print_hold "\r" + indent + " " + options[index] + " "

        index -= 1
        if index < 0
          index = options.count-1 if index < 0
          print_hold "\e[#{options.count-1}B" # move cursor down to the last item
        else
          print_hold "\e[1A" # move cursor up one
        end
        print_hold "\r" + indent + $pastel.black.on_cyan(" " + options[index] + " ")
      elsif char == "\e[B" # DOWN
        # first, remove the highlighting on this item by reprinting before moving the cursor.
        print_hold "\r" + indent + " " + options[index] + " "

        index += 1
        if index == options.count
          index = 0
          print_hold "\e[#{options.count-1}A" # move cursor up to the first item
        else
          print_hold "\e[1B" # move cursor down one
        end
        print_hold "\r" + indent + $pastel.black.on_cyan(" " + options[index] + " ")
      elsif char == "\e[D" # LEFT
      elsif char == "\e[C" # RIGHT
      end

      if char == "\e" or char.ord == 13
        print_hold "\e[#{options.count - index + 1}B" # move cursor to last row
        clear_block(options.count + 6)
        break
      end
    end
    initialize_room_sayings
    show_cursor

    return index if char.first.ord == 13
    nil
  end

  def get_max_array_width(array)
    # find max width of the options
    cur_width = 0
    array.each do |item|
      cur_width = item.length if item.length > cur_width
    end
    max_width = cur_width
    max_width
  end


  def draw_box(heading_text = nil, cols, rows)
    print "\e(0" # enable line drawing mode
    if heading_text.present?
      width = heading_text.length > cols ? heading_text.length : cols
    else
      width = cols
    end
    width += 4 # two spaces on either side for padding


    print_hold "l" # upper-left corner
    print_hold "q" * width
    print "k" # upper-right corner

    if heading_text.present?
      print "x  " + "\e(B" + $pastel.bright_yellow(heading_text) + "\e(0" + "  x"
      print_hold "t"
      print_hold "q" * width
      print "u"
    end

    rows.times do
      print_hold "x"
      print_hold "\e[#{width}C"
      print "x"
    end
    print_hold "m" # bottom-left corner
    print_hold "q" * width
    print "j" # bottom-right corner

    print_hold "\e(B" # disable line drawing mode

    print_hold "\e[#{rows+1}A" # move cursor back to top of box
  end

  def clear_block(num_prev_lines)
    # Position cursor at top of block
    print_hold "\e[#{num_prev_lines}A"
    # Now erase the line
    num_prev_lines.times { print "\e[#{num_prev_lines+5}M" }
    print_hold "\e[#{num_prev_lines}A" # move cursor back to top
  end

  def hide_cursor
    print_hold "\e[?25l"
  end
  def show_cursor
    print_hold "\e[?25h"
  end



  def show_prompt
    print_hold ("\e[38;5;14m\e[1m> \e[0m") # light blue prompt
  end
  def self.show_prompt
    self.print_hold ("\e[38;5;14m\e[1m> \e[0m") # light blue prompt
  end


  def main_loop
    client_thread = Thread.current
    @message_thread = Thread.new do
      loop do
        sleep 0.1
        next if @pause_events
        check_message_queue(client_thread)
        process_event_queue(client_thread)
      end
    end

    # Begin eternal loop
    loop do
      save_player
      print ""
      show_prompt

      loop do # do background events and wait for input
        command = get_input
        if command.present?
          print_hold "\n\r"
          parse_input(command)
          break
        end
      end
    end
  end

  def initialize_room_sayings
    client_thread = Thread.current

    # Room Sayings thread - randomly display any room sayings
    @room_saying_thread = Thread.new do
      index = 0
      loop do
        sleep 5
        if @room_sayings.count > 0 and not @client_thread.nil?
          client_thread[:q] << @room_sayings[index].text
          index += 1
          index = 0 if index > @room_sayings.count - 1
        else
          index = 0
        end
        sleep 5
      end
    end
  end

  def check_message_queue(client_thread)
    messages = client_thread[:q]
    if messages.present? and messages.count > 0
      client_thread[:q] = [] # reset the message queue
      @client.print "\e[2K\r" # erase current line
      messages.each { |msg| @client.puts msg + "\r" }
      show_prompt
      @client.print @input
    end
  end

  def process_event_queue(client_thread)
    event_list = client_thread[:event_q]
    if event_list.present? and event_list.count > 0
      client_thread[:event_q] = [] # reset the event queue

      text = ""
      event_list.each do |event|
        text += event.message if event.message.present?
        process_event(event)
      end

      overprint(text) if text.present?
    end
  end

  def process_event(event)
    case event.action
    when ACTION_EXIT_ROOM, ACTION_ENTER_ROOM, ACTION_TELEPORT_ENTER, ACTION_TELEPORT_EXIT
      @room.npc.reload
      @room.player_characters.reload
    when ACTION_EXIT_GAME, ACTION_ENTER_GAME
      @room.player_characters.reload
    when ACTION_EXIT_CREATE_EXIT, ACTION_ENTER_CREATE_EXIT
      load_room
    when ACTION_SPAWN_CREATURE
      #@room.reload
      @room.creature_instances.reload
      puts "RELOADING CREATURE INSTANCES in room"
    when ACTION_UPDATE_ROOM_DESC
      @room.reload
    when ACTION_HIT
      if event.data[:recipient_name] == @player.name
        @player.receive_attack(event, @overprint)
      else
        overprint event.data[:attacker_name] + " hit " + event.data[:recipient].article + event.data[:recipient_name] + " for " + event.data[:damage].to_s + " damage."
      end
    when ACTION_MISS
      if event.data[:recipient_name] == @player.name
        @player.receive_miss(event, @overprint)
      else
        overprint event.data[:attacker_name] + " attacked " + event.data[:recipient].article + event.data[:recipient_name] + " but missed."
      end
    when ACTION_DIE
      load_room
      if event.data[:attacker_name] != @player.name
        overprint event.data[:attacker_name] + " killed " + event.data[:recipient_def_article] + event.data[:recipient_name] + "."
      end
      if event.data[:attacker_name] == @player.name
        overprint "You killed #{event.data[:recipient_def_article]}#{event.data[:recipient_name]}."
      end
    when ACTION_SAY
      if event.data[:sender_name] != @player.name
        overprint $pastel.bright_yellow(event.data[:sender_name]) + " says, \"" + event.data[:text] + "\""
      end
    end
  end

  def notify_room(player, message, x, y, z)
    World::Manager.notify_room(player.name, message, x, y, z)
  end

  def transport_user(x, y, z, exit_text, enter_text)
    exit_text = "#{@player.name} just disappeared in a puff of smoke!" if exit_text.nil?
    enter_text = "#{@player.name} just appeared in a puff of smoke!" if exit_text.nil?

    notify_room @player, exit_text, @player.x, @player.y, @player.z
    @player.x = x
    @player.y = y
    @player.z = z
    notify_room(@player, enter_text, x, y, z)
    load_room
    print_location
  end

  def dir(dir)
    if !@room.exits.split('').include?(dir)
      print "You can't go that way."
      return
    end

    vector = World::Manager.dir_list.find { |e| e.has_key?(dir.to_sym) }.values.first
    # vector returns a hash like:  {:x=>1, :y=>0, :z=>0}

    World::Manager.room_event(Event.new({ 
      action: ACTION_EXIT_ROOM,
      room: @room,
      message: "#{@player.name} went #{vector[:to_dir]}.",
      data: vector,
      player: @player,
      sender_type: SENDER_TYPE_PLAYER
    }))

    @player.x = @player.x + vector[:x]
    @player.y = @player.y + vector[:y]
    @player.z = @player.z + vector[:z]

    load_room

    World::Manager.room_event(Event.new({ 
      action: ACTION_ENTER_ROOM,
      room: @room,
      message: "#{@player.name} entered from #{vector[:from_dir]}.",
      data: vector,
      player: @player,
      sender_type: SENDER_TYPE_PLAYER
    }))

    print_location
  end

  def create_new_exit(dir)
    dir_key_vals = { n: false, s: false, w: false, e: false, u: false, d: false }
    all_dirs = "nsweud".split('')
    opposite_dirs = "snewdu".split('')
    old_exits = @room.exits.split('')

    all_dirs.each_with_index do |ex, index|
      if ex == dir
        opposite_exit = opposite_dirs[index]
        break
      end
    end
    old_room = @room

    vector = World::Manager.dir_list.find { |e| e.has_key?(dir.to_sym) }.values.first
    # vector returns a hash like:  {:x=>1, :y=>0, :z=>0}

    World::Manager.room_event(Event.new({
      action: ACTION_EXIT_CREATE_EXIT,
      room: @room,
      message: "#{@player.name} created an exit #{vector[:to_dir_verbose]} and went through it.",
      data: vector,
      player: @player,
      sender_type: SENDER_TYPE_PLAYER
    }))

    @player.x = @player.x + vector[:x]
    @player.y = @player.y + vector[:y]
    @player.z = @player.z + vector[:z]

    # Does room need to be created?
    load_room
    if @room.nil?
      new_exit_dir = ""
      all_dirs.each_with_index do |ex, index|
        if ex == dir
          new_exit_dir = opposite_dirs[index]
          break
        end
      end

      # Create new room
      room = Room.new
      room.x = @player.x
      room.y = @player.y
      room.z = @player.z
      room.exits = add_exit(room.exits.split(''), new_exit_dir)

      room.xyz_hash = "#{@player.x},#{@player.y},#{@player.z}"
      room.zone_id = old_room.zone_id
      room.created_by = @player.user.id
      room.description = "You're in an empty space.\n\rType '" + $pastel.bright_yellow("desc") + "' to create a room description. Type '" + $pastel.bright_yellow("room-say") + "' to create room sayings."
      room.save
 
      load_room
      print_location
    end

    World::Manager.room_event(Event.new({
      action: ACTION_ENTER_CREATE_EXIT,
      room: @room,
      message: "#{@player.name} created an exit from #{vector[:from_dir]} and came through it.",
      data: vector,
      player: @player,
      sender_type: SENDER_TYPE_PLAYER
    }))

    # Add exit to old room
    old_room.exits = add_exit(old_room.exits.split(''), dir)
    old_room.save
  end

  def add_exit(existing_exits, dir)
    dir_key_vals = { n: false, s: false, w: false, e: false, u: false, d: false }

    dir_key_vals[dir.to_sym] = true
    existing_exits.each do |ex|
      dir_key_vals[ex.to_sym] = true
    end

    new_exits = ""
    dir_key_vals.keys.each_with_index do |dir, index|
      new_exits += dir.to_s if dir_key_vals.values[index] == true
    end
    new_exits
  end

  def room_say(phrase)
    saying = RoomSaying.new
    saying.text = phrase
    saying.room_id = @room.id
    saying.x = @player.x
    saying.y = @player.y
    saying.z = @player.z
    saying.created_by = @player.user.id
    saying.save
    print $pastel.bright_magenta("Okay, the room can now randomly output that phrase.")
    load_room
  end

  def desc(phrase)
    @room.description = phrase
    @room.save
    print "Room description changed.\n"
    World::Manager.room_event(Event.new({
      action: ACTION_UPDATE_ROOM_DESC,
      room: @room,
      message: "#{@player.name} change the room's description. Type 'look' to see it.",
      player: @player,
      sender_type: SENDER_TYPE_PLAYER
    }))
    load_room
    print_location
  end

  def load_room(x = @player.x, y = @player.y, z = @player.z)
    @room_saying_thread.kill if @room_saying_thread.present?
    @room = Room.find_by(xyz_hash: "#{x},#{y},#{z}")
    if @room.present?
      @room_sayings = RoomSaying.where(room_id: @room.id)
      initialize_room_sayings
      @player.room_id = @room.id
      @player.save
    end

  end

  def print_location
    exit_list = "none"
    print $pastel.bright_white.on_blue(" " + @room.name + " ") if @room.name.present?
    print @room.description

    if @room.exits.present?
      exit_list = @room.exits.split('').join(', ')
    end


    exits = "Exits: " + exit_list
    print $pastel.bright_cyan(exits)

    # Players in room
    players_in_room = @room.player_characters
    if players_in_room.present?
      players_in_room.each do |player|
        next if player.name == @player.name
        print $pastel.bright_yellow(player.name) + " is here."
      end
    end

    # NPCs in room
    npcs = @room.npc
    if npcs.present?
      npcs.each_with_index do |npc, i|
        print_hold $pastel.bright_yellow(npc.npc_name)
        print_hold ", " if npcs.count > 1 and i < npcs.count - 2
        print_hold " and " if npcs.count > 1 and i == npcs.count - 2
      end
      print " is here." if npcs.count == 1
      print " are here." if npcs.count > 1
    end

    # Creatures in room
    creatures = @room.creature_instances
    puts "CREATURES IN ROOM:"
    ap creatures
    if creatures.present?
      print_hold "There is "
      creatures.each_with_index do |instance, i|
        print_hold vanna(instance.creature_name)
        print_hold ", " if creatures.count > 1 and i < creatures.count - 2
        print_hold " and " if creatures.count > 1 and i == creatures.count - 2
      end
      print " here." if creatures.count == 1
      print " here." if creatures.count > 1
    end
  end


  def vanna(text)
    # Is the first letter a vowel?
    return_val = text[0] =~ /[aeiouAEIOU]/ ? "an " : "a "
    return return_val + text
  end

  def get_screen_size
    # send IAC codes to move cursor to col/row 9999/9999, then ask client where the cursor actually is. This is the terminal window size.
    print_hold "\0337\033[r\033[9999;9999H" + "\033[6n"
    puts "Screen Size:"
    response_code = ""
    while true
      d = @client.getc
      break if d == "R"
      response_code += d
    end
    size = response_code[2..-1].split(";")
    @screen_params = {
      rows: size.first.to_i,
      cols: size.second.to_i
    }
    @screen_params
  end

  def screen_header(text, center = false)
    size = get_screen_size
    print_hold $pastel.bright_cyan('')
    if center
      indent = (((size[:cols] - text.length) / 2).to_i - 1) * " "
      print_hold "\e[2J\e[H\e[7m"
      print_hold indent + " #{text} " + indent
      print "\e[0m\n"
    else
      print "\e[2J\e[H\e[7m #{text} \e[0m\n"
    end
  end

  def npc_new
    @pause_events = true
    while true
      print_hold $pastel.bright_yellow("\nNPC Name: ")
      npc_name = get_line

      # An NPC must be unique. No copies or spawned instances of NPCs are allowed.
      npc = NPC.where(npc_name: npc_name)
      pc = PlayerCharacter.where(name: npc_name)
      break if pc.empty? and npc.empty?
      print "This name is already in use by a player or another NPC. Please choose a different name.\n"
    end

    question = "Will the NPC move about randomly or be stationary in this room?"
    options = ["Move Randomly", "Stationary"]
    can_roam = scrolling_menu(question, options)
    print $pastel.bright_yellow("NPC Movement: ") + options[can_roam]
    can_roam = can_roam == 0

    print_hold $pastel.bright_yellow("Hit Point Max: ")
    hitmax = get_line

    print_hold $pastel.bright_yellow("Strength: ")
    strength = get_line

    print_hold $pastel.bright_yellow("Bravery: ")
    bravery = get_line

    print_hold $pastel.bright_yellow("Dexterity: ")
    dexterity = get_line

    print_hold $pastel.bright_yellow("Credits: ")
    credits = get_line

    puts "1"
    npc = NPC.new
    puts "2"
    #npc.npc_name = npc_name
    puts "3"
    npc.room_id = @room.id
    puts "4"
    npc.can_roam = can_roam
    puts "5"
    npc.hitmax = hitmax
    puts "6"
    npc.hp = hitmax
    puts "7"
    npc.strength = strength
    puts "8"
    npc.bravery = bravery
    puts "9"
    npc.dexterity = dexterity
    puts "10"
    npc.credits = credits
    puts "10"
    npc.created_by = @player.id
    puts "11"
    npc.save
    puts "12"

    @pause_events = false

    print "The NPC named '" + $pastel.bright_yellow(npc.npc_name) + "' has been added to the room.\n"

    print_location
  end


  def find_entity_in_room(name)
    creatures = @room.creature_instances
    result = creatures.find do |instance|
      instance.creature_name.downcase.include? name.downcase
    end
    return { entity: result, type: :creature } if result.present?

    npcs = @room.npc
    result = npcs.find do |npc|
      npc.npc_name.downcase.include? name.downcase
    end
    ap result
    return { entity: result, type: :npc } if result.present?

    players = @room.player_characters
    result = players.find do |player|
      player.name.downcase.include? name.downcase
    end
    return { entity: result, type: :player } if result.present?
  end
end

