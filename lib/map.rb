def show_map(rooms, room_id = nil, screen_params)
  room = rooms.find_by(id: room_id)
  if room.nil?
    print "You are in an unknown location.\r\n"
    return
  end

  # Is user in an automated ship?
  ship = Ship.where(is_automated: true).find { |s| s.home_room_id == room_id }
  if ship and room.exits == ""
    # ASCII map of a one-room spaceship
    print "     _"
    print "    / \\"
    print "   /---\\"
    print "  ,| #{$pastel.bright_blue("X")} |."
    print " //+---+\\\\"
    return
  end

  max_cols = screen_params[:cols].to_i
  max_rows = screen_params[:rows].to_i - 8

  # Guard against tiny terminals
  if max_cols < 5 || max_rows < 3
    print "Screen too small to render a map.\r\n"
    return
  end

  # Never render more than the client reports
  map_width = max_cols
  map_height = max_rows

  # Rooms share borders. First room takes 5x3 chars; each additional room adds 4 cols and 2 rows.
  # Total width for N rooms: 5 + (N - 1) * 4 = 4N + 1
  # Total height for N rooms: 3 + (N - 1) * 2 = 2N + 1
  rooms_w = ((map_width - 1) / 4).floor
  rooms_h = ((map_height - 1) / 2).floor
  rooms_w = 1 if rooms_w < 1
  rooms_h = 1 if rooms_h < 1

  half_rooms_w = (rooms_w / 2).floor
  half_rooms_h = (rooms_h / 2).floor

  top_left_x = room.x.to_i - half_rooms_w
  top_left_y = room.y.to_i - half_rooms_h
  bottom_right_x = room.x.to_i + half_rooms_w
  bottom_right_y = room.y.to_i + half_rooms_h

  # Create an ASCII map grid that fits in map_width and map_height (so it doesn't extend past player's screen)
  # Each room should be 5 characters wide and 3 characters tall
  # So the total map size in rooms is map_width / 3 and map_height / 3

  # If a room has exits like "ns" (north, south), draw the room like this:
  #  +   +
  #  |   |
  #  +   +
  # For an exit "e", draw like this:
  # +---+
  # |
  # +---+
  # For an exit "wud" (west, up, down), draw like this:
  # +---+
  #  ^ v|
  # +---+

  # Mapped rooms will share walls, so we need to account for that in the drawing
  map_grid = Array.new(map_height) { Array.new(map_width, ' ') }

  rooms_in_map = rooms.where(zone_id: room.zone_id, z: room.z, x: (top_left_x..bottom_right_x), y: (top_left_y..bottom_right_y))
                    .index_by { |r| [r.x, r.y] }

  player_grid_x = nil
  player_grid_y = nil

  rooms_in_map.each do |(x, y), r|
    grid_x = (x - top_left_x) * 4
    grid_y = (y - top_left_y) * 2

    # Skip any rooms that don't fully fit in the drawable grid
    next if grid_x < 0 || grid_y < 0
    next if (grid_x + 4) >= map_width || (grid_y + 2) >= map_height

    exits = r.exits.to_s

    n_room = rooms_in_map[[x, y - 1]]
    s_room = rooms_in_map[[x, y + 1]]
    e_room = rooms_in_map[[x + 1, y]]
    w_room = rooms_in_map[[x - 1, y]]

    n_exits = n_room&.exits.to_s
    s_exits = s_room&.exits.to_s
    e_exits = e_room&.exits.to_s
    w_exits = w_room&.exits.to_s

    open_n = exits.include?('n') && !n_room.nil? && n_exits.include?('s')
    open_s = exits.include?('s') && !s_room.nil? && s_exits.include?('n')
    open_e = exits.include?('e') && !e_room.nil? && e_exits.include?('w')
    open_w = exits.include?('w') && !w_room.nil? && w_exits.include?('e')

    # Draw room box
    map_grid[grid_y][grid_x] = '+'
    map_grid[grid_y][grid_x + 4] = '+'
    map_grid[grid_y + 2][grid_x] = '+'
    map_grid[grid_y + 2][grid_x + 4] = '+'

    # Draw horizontal walls
    (1..3).each do |i|
      map_grid[grid_y][grid_x + i] = '-' unless open_n
      map_grid[grid_y + 2][grid_x + i] = '-' unless open_s
    end

    # Draw vertical walls
    map_grid[grid_y + 1][grid_x] = '|' unless open_w
    map_grid[grid_y + 1][grid_x + 4] = '|' unless open_e

    # Draw exits (only carve openings when reciprocal + neighbor exists)
    exits.each_char do |exit_dir|
      case exit_dir
      when 'n'
        map_grid[grid_y][grid_x + 2] = ' ' if open_n
      when 's'
        map_grid[grid_y + 2][grid_x + 2] = ' ' if open_s
      when 'e'
        map_grid[grid_y + 1][grid_x + 4] = ' ' if open_e
      when 'w'
        map_grid[grid_y + 1][grid_x] = ' ' if open_w
      when 'u'
        map_grid[grid_y][grid_x + 3] = '^'
      when 'd'
        map_grid[grid_y + 2][grid_x + 3] = 'v'
      end
    end

    # Mark player location in the center of the current room
    if r.id == room.id
      player_grid_x = grid_x + 2
      player_grid_y = grid_y + 1
      map_grid[player_grid_y][player_grid_x] = $pastel.bright_blue("X")
    end
  end

  # Print the map.
  # If the map fits within the client's size, trim empty leading rows/cols and render it at top-left.
  # If it doesn't fit, crop to the client's size centered on the player so mobile terminals don't wrap.

  player_grid_x ||= (map_width / 2)
  player_grid_y ||= (map_height / 2)

  # Build printable lines (rstrip to avoid trailing whitespace scrollback)
  raw_lines = map_grid.map { |row| row.join.rstrip }

  # Find bounding box of non-empty content
  non_empty_rows = raw_lines.each_index.select { |i| !raw_lines[i].strip.empty? }

  if non_empty_rows.empty?
    # Nothing to render
    return
  end

  min_row = non_empty_rows.min
  max_row = non_empty_rows.max

  non_empty_lines = raw_lines[min_row..max_row]
  min_col = non_empty_lines.reject { |l| l.strip.empty? }.map { |l| (l[/\A */] || '').length }.min || 0
  content_width = non_empty_lines.map { |l| l.rstrip.length }.max.to_i - min_col
  content_height = non_empty_lines.length

  # ANSI-safe truncation by visible width (keeps colored X from causing wrap)
  truncate_ansi = lambda do |str, max_visible|
    out = +""
    visible = 0
    i = 0

    while i < str.length && visible < max_visible
      ch = str[i]

      # ANSI escape sequence
      if ch == "\e"
        m = str.index('m', i)
        if m
          out << str[i..m]
          i = m + 1
          next
        else
          break
        end
      end

      out << ch
      visible += 1
      i += 1
    end

    out << "\e[0m" if out.include?("\e")
    out
  end

  fits = (content_width <= max_cols) && (content_height <= max_rows)

  if fits
    # Top-left mode: trim empty top/left and print only the content bounds
    non_empty_lines.each_with_index do |line, idx|
      break if idx >= max_rows
      trimmed = line[min_col..] || ""
      trimmed = truncate_ansi.call(trimmed, max_cols)
      print trimmed
    end
  else
    # Cropped mode: center crop window on the player
    left = player_grid_x - (max_cols / 2)
    top  = player_grid_y - (max_rows / 2)

    left = 0 if left < 0
    top = 0 if top < 0

    # Clamp so window stays within the grid
    if left + max_cols > map_width
      left = map_width - max_cols
      left = 0 if left < 0
    end
    if top + max_rows > map_height
      top = map_height - max_rows
      top = 0 if top < 0
    end

    right = left + max_cols - 1

    (top...(top + max_rows)).each do |row_i|
      break if row_i >= map_height

      row = map_grid[row_i]
      next if row.nil?

      segment = row[left..right] || []
      line = segment.join

      # Ensure the client never sees more than max_cols visible characters
      line = truncate_ansi.call(line, max_cols)
      print line
    end
  end
end
