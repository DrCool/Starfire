require "json"
require "set"

module ZonePreviewBuilder
  ORDER = %w[n s w e u d].freeze
  OPP = { "n" => "s", "s" => "n", "w" => "e", "e" => "w", "u" => "d", "d" => "u" }.freeze

  # Convention: north/west/up decrement; south/east/down increment
  DELTA = {
    "n" => [0, -1, 0],
    "s" => [0, 1, 0],
    "w" => [-1, 0, 0],
    "e" => [1, 0, 0],
    "u" => [0, 0, -1],
    "d" => [0, 0, 1],
  }.freeze

  Edge = Struct.new(:a, :b, :kind, keyword_init: true)

  class ValidationError < StandardError; end
  class EmbeddingError < StandardError; end

  # Best-effort pipeline: try strict validation + embedding first; if that fails,
  # progressively repair the graph and/or relax constraints so we always return
  # at least something playable.
  def self.build_preview_rooms_from_llm_json_best_effort!(
    data,
    zone_id:,
    created_by:,
    start_x: -100,
    start_y: -100,
    start_z: -100
  )

    attempts = []

    # 1) strict as-is
    attempts << { label: :strict, data: data, edge_mode: :original }

    # 2) repaired ids/edges/connectivity (keep as many edges as possible)
    repaired = repair_data_best_effort(data)
    attempts << { label: :repaired, data: repaired, edge_mode: :original }

    # 3) spanning tree edges only (fewer constraints)
    attempts << { label: :spanning_tree, data: repaired, edge_mode: :spanning_tree }

    # 4) chain edges (maximally embeddable)
    attempts << { label: :chain, data: repaired, edge_mode: :chain }

    # 5) no edges (always place rooms linearly)
    attempts << { label: :no_edges, data: repaired, edge_mode: :none }

    last_error = nil

    attempts.each do |a|
      begin
        ids, edges, room_payload_by_id = validate_and_normalize_best_effort!(a[:data])

        edges_for_embed = case a[:edge_mode]
                          when :original
                            edges
                          when :spanning_tree
                            spanning_tree_edges(ids, edges)
                          when :chain
                            chain_edges(ids)
                          when :none
                            []
                          else
                            edges
                          end

        pos_by_id = case a[:edge_mode]
                    when :none
                      embed_linear!(ids, start_x, start_y, start_z)
                    when :chain
                      embed_chain_snake!(ids, start_x, start_y, start_z)
                    else
                      embed_backtracking_with_restarts!(ids, edges_for_embed, start_x, start_y, start_z)
                    end

        puts "ZonePreviewBuilder: using attempt=#{a[:label]} edge_mode=#{a[:edge_mode]} rooms=#{ids.size} edges=#{edges_for_embed.size}"
        return build_rooms_from_embedded!(
          ids,
          edges_for_embed,
          room_payload_by_id,
          pos_by_id,
          zone_id: zone_id,
          created_by: created_by
        )
      rescue ValidationError, EmbeddingError, JSON::ParserError => e
        last_error = e
        next
      rescue StandardError => e
        last_error = e
        next
      end
    end

    raise(last_error || EmbeddingError.new("Embedding failed: exhausted best-effort attempts"))
  end

  # Always succeeds: snake pattern so consecutive ids are adjacent.
  def self.embed_chain_snake!(ids, start_x, start_y, start_z)
    cols = (Math.sqrt(ids.length) * 2.2).ceil
    cols = [[cols, 8].max, 30].min

    pos_by_id = {}
    ids.each_with_index do |rid, i|
      row = i / cols
      col = i % cols
      x = row.even? ? (start_x + col) : (start_x + (cols - 1 - col))
      y = start_y + row
      pos_by_id[rid] = [x, y, start_z]
    end
    pos_by_id
  end

  # Repairs common LLM issues:
  # - missing/duplicate room ids
  # - non-contiguous ids (renumber to R001..)
  # - edges referencing missing rooms
  # - duplicate/self edges
  # - disconnected graphs (adds repair edges)
  def self.repair_data_best_effort(data)
    data = data.is_a?(Hash) ? data.dup : { "rooms" => [], "edges" => [] }

    rooms_arr = data["rooms"].is_a?(Array) ? data["rooms"].dup : []
    edges_arr = data["edges"].is_a?(Array) ? data["edges"].dup : []

    # Ensure each room has an id; if not, synthesize.
    rooms_arr = rooms_arr.map.with_index(1) do |r, idx|
      r = r.is_a?(Hash) ? r.dup : {}
      r["id"] = r["id"].to_s.strip
      r["id"] = "TMP#{idx}" if r["id"].empty?
      r
    end

    # Deduplicate room ids while preserving first payload.
    seen = Set.new
    uniq_rooms = []
    rooms_arr.each do |r|
      rid = r["id"]
      next if seen.include?(rid)
      seen << rid
      uniq_rooms << r
    end

    # Renumber to contiguous R001..R### to satisfy downstream expectations.
    old_to_new = {}
    new_rooms = []
    uniq_rooms.each_with_index do |r, i|
      new_id = format("R%03d", i + 1)
      old_to_new[r["id"]] = new_id
      nr = r.dup
      nr["id"] = new_id
      new_rooms << nr
    end

    id_set = new_rooms.map { |r| r["id"] }.to_set

    # Sanitize edges against renumbered ids.
    seen_edges = Set.new
    new_edges = []
    edges_arr.each do |e|
      next unless e.is_a?(Hash)
      a0 = e["a"]
      b0 = e["b"]
      next if a0.nil? || b0.nil?
      a = old_to_new[a0] || old_to_new[a0.to_s] || a0
      b = old_to_new[b0] || old_to_new[b0.to_s] || b0
      next unless id_set.include?(a) && id_set.include?(b)
      next if a == b

      kind = (e["kind"] || "").to_s
      k = edge_key(a, b, kind)
      next if seen_edges.include?(k)
      seen_edges << k
      new_edges << { "a" => a, "b" => b, "kind" => kind }
    end

    # If graph is disconnected, connect components with repair edges.
    comps = connected_components(id_set.to_a, new_edges)
    if comps.size > 1
      anchor = comps.first.first
      comps[1..].each do |comp|
        new_edges << { "a" => anchor, "b" => comp.first, "kind" => "" }
        anchor = comp.first
      end
    end

    { "rooms" => new_rooms, "edges" => new_edges }
  end

  def self.connected_components(ids, edges_hashes)
    adj = Hash.new { |h, k| h[k] = [] }
    ids.each { |id| adj[id] = [] }
    edges_hashes.each do |e|
      a = e["a"]; b = e["b"]
      next if a.nil? || b.nil?
      next unless adj.key?(a) && adj.key?(b)
      adj[a] << b
      adj[b] << a
    end

    unvisited = ids.to_set
    comps = []

    while (start = unvisited.first)
      stack = [start]
      comp = []
      while (cur = stack.pop)
        next unless unvisited.delete?(cur)
        comp << cur
        adj[cur].each { |n| stack << n if unvisited.include?(n) }
      end
      comps << comp
    end

    comps
  end

  def self.spanning_tree_edges(ids, edges)
    adj = build_adj(ids, edges)
    start = ids.first
    visited = Set.new([start])
    stack = [start]
    tree = []

    while (cur = stack.pop)
      adj[cur].each do |(to, kind)|
        next if visited.include?(to)
        visited.add(to)
        stack << to
        tree << Edge.new(a: cur, b: to, kind: kind)
      end
    end

    # If disconnected, chain remaining rooms (should be rare after repair)
    if visited.size < ids.size
      remaining = ids.reject { |rid| visited.include?(rid) }
      anchor = start
      remaining.each do |rid|
        tree << Edge.new(a: anchor, b: rid, kind: "")
        anchor = rid
      end
    end

    tree
  end

  def self.chain_edges(ids)
    out = []
    (0...(ids.length - 1)).each do |i|
      out << Edge.new(a: ids[i], b: ids[i + 1], kind: "")
    end
    out
  end

  # Always succeeds: places rooms in a simple eastward line.
  # Always succeeds: places rooms in a wrapped 2D grid (not a single line).
  def self.embed_linear!(ids, start_x, start_y, start_z)
    cols = (Math.sqrt(ids.length) * 2.2).ceil
    cols = [[cols, 8].max, 30].min

    pos_by_id = {}
    ids.each_with_index do |rid, i|
      row = i / cols
      col = i % cols
      pos_by_id[rid] = [start_x + col, start_y + row, start_z]
    end
    pos_by_id
  end
  # Extracted from build_preview_rooms_from_llm_json!: given ids/edges/payload/positions,
  # build unsaved Room objects.
  def self.build_rooms_from_embedded!(ids, edges, room_payload_by_id, pos_by_id, zone_id:, created_by:)
    # Derive reciprocal directed links from coordinates
    directed_links = []
    edges.each do |e|
      ax, ay, az = pos_by_id.fetch(e.a)
      bx, by, bz = pos_by_id.fetch(e.b)
      dx = bx - ax
      dy = by - ay
      dz = bz - az

      dir_ab = nil
      if e.kind == "vertical"
        # Up means z-1, Down means z+1
        dir_ab = "u" if dz == -1
        dir_ab = "d" if dz == 1
      else
        # North means y-1, South means y+1
        dir_ab = "e" if dx == 1
        dir_ab = "w" if dx == -1
        dir_ab = "n" if dy == -1
        dir_ab = "s" if dy == 1
      end

      # In best-effort mode, skip any edge that ended up non-adjacent due to repairs/fallbacks.
      next unless dir_ab

      directed_links << { from: e.a, dir: dir_ab, to: e.b }
      directed_links << { from: e.b, dir: OPP.fetch(dir_ab), to: e.a }
    end

    directed_links = sanitize_directed_links!(ids, directed_links, pos_by_id)
    exits_by_id = compute_exits(ids, directed_links)

    now = Time.now

    counter = 0
    rooms_arr = ids.map.with_index(1) do |rid, _idx|
      payload = room_payload_by_id[rid] || {}
      counter += 1

      id = counter
      x, y, z = pos_by_id.fetch(rid)
      xyz_hash = "#{x},#{y},#{z}"

      inside = (payload["inside"] || 0).to_i
      outside = (payload["outside"] || 0).to_i
      if inside == 1 && outside == 1
        outside = 0
      elsif inside == 0 && outside == 0
        outside = 1
      end

      Room.new(
        zone_id: zone_id,
        exits: exits_by_id.fetch(rid),
        id: id,
        x: x,
        y: y,
        z: z,
        xyz_hash: xyz_hash,

        name: payload["name"] || rid,
        description: payload["description"] || "",
        verbose_description: payload["verbose_description"] || "",

        inside: inside,
        outside: outside,
        terrain_type_id: payload["terrain_type_id"],
        created_at: now,
        updated_at: now,
        created_by: created_by,
        credits_on_ground: 0,
        room_type_id: payload["room_type_id"]
      )
    end
    RoomCollection.new(rooms_arr)
  end

  # Best-effort validation/normalization:
  # - If the schema is wrong, attempt to coerce it; only raise if we end up with no rooms.
  def self.validate_and_normalize_best_effort!(data)
    begin
      return validate_and_normalize!(data)
    rescue ValidationError
      repaired = repair_data_best_effort(data)
      ids, edges, payload = validate_and_normalize!(repaired)
      return [ids, edges, payload]
    end
  end

  # Public API
  #
  # json_text: the raw JSON string from the LLM
  # zone_id/created_by: required (your Room schema requires them)
  # start_x/y/z: defaults to -100,-100,-100
  #
  # Returns: Array<Room> (unsaved)
  def self.build_preview_rooms_from_llm_json!(
    data,
    zone_id:,
    created_by:,
    start_x: -100,
    start_y: -100,
    start_z: -100
  )
    build_preview_rooms_from_llm_json_best_effort!(
      data,
      zone_id: zone_id,
      created_by: created_by,
      start_x: start_x,
      start_y: start_y,
      start_z: start_z
    )
  end

  # Optional helper: index rooms by [x,y] for your map renderer
  def self.index_by_xy(rooms)
    rooms.each_with_object({}) do |r, h|
      h[[r.x, r.y]] = r
    end
  end

  # Wraps an Array<Room> and provides a tiny subset of ActiveRecord-ish query helpers
  # used by map rendering code (e.g., .find_by, .where). All operations are in-memory.
  class RoomCollection
    include Enumerable

    def initialize(rooms)
      @rooms = rooms
      @by_id = nil
    end

    def each(&block)
      @rooms.each(&block)
    end

    def to_a
      @rooms
    end

    def index_by
      return enum_for(:index_by) unless block_given?
      @rooms.index_by { |r| yield(r) }
    end

    def find_by(**kwargs)
      if kwargs.key?(:id)
        id = kwargs[:id]
        @by_id ||= @rooms.each_with_object({}) { |r, h| h[r.id] = r }
        return @by_id[id]
      end

      @rooms.find do |r|
        kwargs.all? do |k, v|
          r.respond_to?(k) && r.public_send(k) == v
        end
      end
    end

    # Supports simple hash filters used by map code, e.g.
    # where(zone_id: 3, z: 10, x: (a..b), y: (c..d))
    def where(**filters)
      out = @rooms.select do |r|
        filters.all? do |k, v|
          next false unless r.respond_to?(k)
          rv = r.public_send(k)

          if v.is_a?(Range)
            rv && v.cover?(rv)
          elsif v.is_a?(Array)
            v.include?(rv)
          else
            rv == v
          end
        end
      end

      RoomCollection.new(out)
    end

    # Delegate other Array-ish methods as needed
    def method_missing(name, *args, &block)
      if @rooms.respond_to?(name)
        @rooms.public_send(name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      @rooms.respond_to?(name, include_private) || super
    end
  end

  # ---------------------------
  # Validation / normalization
  # ---------------------------

  def self.edge_key(a, b, kind)
    s1, s2 = [a, b].sort
    "#{s1}|#{s2}|#{kind}"
  end

  def self.validate_and_normalize!(data)
    unless data.is_a?(Hash) && data["rooms"].is_a?(Array) && data["edges"].is_a?(Array)
      raise ValidationError, "Input must be JSON object with rooms[] and edges[]"
    end

    rooms_arr = data["rooms"]
    edges_arr = data["edges"]

    ids = rooms_arr.map { |r| r["id"] }
    raise ValidationError, "rooms[].id missing" if ids.any?(&:nil?)

    ids.each do |id|
      raise ValidationError, "Bad room id: #{id.inspect}" unless id.is_a?(String) && id.match?(/\AR\d{3}\z/)
    end

    sorted = ids.sort
    # Strict contiguity is ideal, but in best-effort mode we may have already repaired.
    # Keep the check, but only enforce it when ids appear to already be in the R### format.
    if sorted.all? { |id| id.is_a?(String) && id.match?(/\AR\d{3}\z/) }
      sorted.each_with_index do |id, i|
        expect = format("R%03d", i + 1)
        raise ValidationError, "Room ids must be contiguous from R001. Expected #{expect}, got #{id}" if id != expect
      end
    end

    id_set = sorted.to_set

    # Keep the LLM-provided room payloads by id (for name/desc/etc)
    payload_by_id = {}
    rooms_arr.each do |r|
      payload_by_id[r["id"]] = r
    end

    seen_edges = Set.new
    edges = edges_arr.map do |e|
      a = e["a"]
      b = e["b"]
      kind = e["kind"] || ""

      raise ValidationError, "Edge missing a/b: #{e.inspect}" if a.nil? || b.nil?
      raise ValidationError, "Edge references missing room: #{e.inspect}" unless id_set.include?(a) && id_set.include?(b)
      raise ValidationError, "Self-edge not allowed: #{e.inspect}" if a == b

      k = edge_key(a, b, kind)
      raise ValidationError, "Duplicate edge: #{k}" if seen_edges.include?(k)
      seen_edges << k

      Edge.new(a: a, b: b, kind: kind)
    end

    # Connectedness (undirected)
    adj = Hash.new { |h, k| h[k] = [] }
    sorted.each { |id| adj[id] = [] }
    edges.each do |e|
      adj[e.a] << [e.b, e.kind]
      adj[e.b] << [e.a, e.kind]
    end

    start = "R001"
    q = [start]
    visited = Set.new
    until q.empty?
      cur = q.shift
      next if visited.include?(cur)
      visited << cur
      adj[cur].each do |(to, _)|
        q << to unless visited.include?(to)
      end
    end

    if visited.size != sorted.size
      missing = sorted.reject { |x| visited.include?(x) }
      # In strict mode this is an error, but the best-effort wrapper will repair connectivity.
      raise ValidationError, "Graph not connected from R001. Unreachable: #{missing.join(", ")}"
    end

    [sorted, edges, payload_by_id]
  end

  # ---------------------------
  # Embedding (backtracking MRV)
  # ---------------------------

  def self.build_adj(ids, edges)
    adj = Hash.new { |h, k| h[k] = [] }
    ids.each { |id| adj[id] = [] }
    edges.each do |e|
      adj[e.a] << [e.b, e.kind]
      adj[e.b] << [e.a, e.kind]
    end
    adj
  end

  def self.embed_backtracking!(ids, edges, start_x, start_y, start_z, max_seconds: 0.8, max_steps: 250_000, rng: Random.new)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + max_seconds.to_f
    steps = 0

    adj = build_adj(ids, edges)
    degree = ids.each_with_object({}) { |id, h| h[id] = adj[id].length }

    pos_by_id = {}     # id -> [x,y,z]
    id_by_pos = {}     # [x,y,z] -> id

    seeded = ids.first
    pos_by_id[seeded] = [start_x, start_y, start_z]
    id_by_pos[[start_x, start_y, start_z]] = seeded

    manhattan1 = ->(a, b) { (a[0] - b[0]).abs + (a[1] - b[1]).abs == 1 && a[2] == b[2] }
    vertical1  = ->(a, b) { a[0] == b[0] && a[1] == b[1] && (a[2] - b[2]).abs == 1 }

    is_free = ->(x, y, z) { !id_by_pos.key?([x, y, z]) }

    placed_neighbors = lambda do |id|
      pn = adj[id].select { |(to, _kind)| pos_by_id.key?(to) }
      # Prefer higher-degree neighbors first, but randomize ties
      pn.sort_by { |(to, _)| [-degree[to], rng.rand] }
    end

    candidates_around = lambda do |nei_id, kind|
      p = pos_by_id[nei_id]
      return [] unless p
      x, y, z = p

      if kind == "vertical"
        return [[x, y, z + 1], [x, y, z - 1]]
      end

      # Prefer E/W first to encourage boulevard-like layouts
      [[x + 1, y, z], [x - 1, y, z], [x, y + 1, z], [x, y - 1, z]]
    end

    satisfies_neighbors = lambda do |id, candidate|
      adj[id].each do |(to, kind)|
        next unless pos_by_id.key?(to)
        np = pos_by_id[to]
        if kind == "vertical"
          return false unless vertical1.call(candidate, np)
        else
          return false unless manhattan1.call(candidate, np)
        end
      end
      true
    end

    score_candidate = lambda do |id, candidate|
      score = 0
      adj[id].each do |(to, kind)|
        next unless pos_by_id.key?(to)
        np = pos_by_id[to]
        if kind == "vertical"
          score += 1 if vertical1.call(candidate, np)
        else
          score += 1 if manhattan1.call(candidate, np)
        end
      end
      score
    end

    candidates_for_id = lambda do |id|
      placed = placed_neighbors.call(id)
      return [] if placed.empty?

      seen = Set.new
      out = []

      placed.each do |(pn_id, kind)|
        candidates_around.call(pn_id, kind).each do |c|
          next if seen.include?(c)
          seen << c
          out << c
        end
      end

      # Primary ordering: maximize satisfied neighbors; then stable-ish ordering,
      # but randomize ties so restarts explore different branches.
      out.sort_by { |c| [-score_candidate.call(id, c), c[2], c[1], c[0], rng.rand] }
    end

    all_placed = -> { pos_by_id.size == ids.size }

    next_unplaced_id = lambda do
      best_id = nil
      best_pn = -1
      best_cc = Float::INFINITY

      ids.each do |id|
        next if pos_by_id.key?(id)
        placed = placed_neighbors.call(id)
        next if placed.empty?

        viable = 0
        candidates_for_id.call(id).each do |c|
          x, y, z = c
          next unless is_free.call(x, y, z)
          next unless satisfies_neighbors.call(id, c)
          viable += 1
          # Small early stop helps performance
          break if viable > 50
        end

        pn = placed.length
        cc = viable

        if pn > best_pn || (pn == best_pn && cc < best_cc)
          best_id = id
          best_pn = pn
          best_cc = cc
        end
      end

      best_id
    end

    check_budget = lambda do
      steps += 1
      if steps >= max_steps
        raise EmbeddingError, "Embedding timed out (step budget exceeded)."
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise EmbeddingError, "Embedding timed out (time budget exceeded)."
      end
    end

    backtrack = lambda do
      check_budget.call
      return true if all_placed.call

      id = next_unplaced_id.call
      return false unless id

      candidates_for_id.call(id).each do |c|
        check_budget.call
        x, y, z = c
        next unless is_free.call(x, y, z)
        next unless satisfies_neighbors.call(id, c)

        pos_by_id[id] = [x, y, z]
        id_by_pos[[x, y, z]] = id

        return true if backtrack.call

        id_by_pos.delete([x, y, z])
        pos_by_id.delete(id)
      end

      false
    end

    ok = backtrack.call
    raise EmbeddingError, "Embedding failed: could not place all rooms to satisfy all edges." unless ok

    pos_by_id
  end

  # Prevents pathological backtracking runs from chewing CPU forever.
  # Tries several short randomized runs; if none succeed, raises EmbeddingError
  # so the best-effort pipeline can fall back to spanning_tree/chain/none.
  def self.embed_backtracking_with_restarts!(ids, edges, start_x, start_y, start_z, restarts: 6, per_restart_seconds: 0.9, max_steps: 250_000)
    last_error = nil

    restarts.to_i.times do
      begin
        rng = Random.new(Random.rand(1 << 30))
        return embed_backtracking!(
          ids,
          edges,
          start_x,
          start_y,
          start_z,
          max_seconds: per_restart_seconds,
          max_steps: max_steps,
          rng: rng
        )
      rescue EmbeddingError => e
        last_error = e
        next
      end
    end

    raise(last_error || EmbeddingError.new("Embedding failed after restarts."))
  end

  # ---------------------------
  # Exits + sanitization
  # ---------------------------

  def self.sanitize_directed_links!(ids, directed_links, pos_by_id)
    by_pos = {}
    ids.each do |id|
      x, y, z = pos_by_id.fetch(id)
      by_pos[[x, y, z]] = id
    end

    kept = []
    directed_links.each do |l|
      from = l[:from]
      dir  = l[:dir]
      to   = l[:to]

      p = pos_by_id[from]
      next unless p

      dx, dy, dz = DELTA[dir]
      key = [p[0] + dx, p[1] + dy, p[2] + dz]
      expected_to = by_pos[key]

      next unless expected_to
      next unless expected_to == to

      kept << l
    end

    kept
  end

  def self.compute_exits(ids, directed_links)
    exits_set = Hash.new { |h, k| h[k] = Set.new }
    ids.each { |id| exits_set[id] = Set.new }

    directed_links.each do |l|
      exits_set[l[:from]] << l[:dir]
    end

    ids.each_with_object({}) do |id, h|
      h[id] = ORDER.select { |d| exits_set[id].include?(d) }.join
    end
  end
end