# frozen_string_literal: true
#
# StarFire Map Graph Generator
# - Configurable room count (default 35)
# - Multiple map types: city_core, dungeon_maze, multi_level_city, multi_level_dungeon,
#   hub_and_spoke, branching_river, lattice, chain_of_clusters
# - Guaranteed minimum number of single-exit rooms (degree == 1) for service rooms
#   like bar/bank/shop/training hall (default min_leaf_rooms: 6).
#
# Public API:
#   generate_starfire_map(type: :dungeon_maze, room_count: 35, seed: 123, **opts)
# Returns:
#   { "rooms" => [{"id"=>"R001"}, ...], "edges" => [{"a"=>"R001","b"=>"R002"}, {"a"=>"R010","b"=>"R020","kind"=>"vertical"}] }

class MapGraph
  Edge = Struct.new(:a, :b, :kind, keyword_init: true) do
    def key
      x, y = [a, b].sort
      [x, y, kind]
    end
  end

  attr_reader :room_ids, :edges

  def initialize(room_count: 35, rng: Random.new)
    raise ArgumentError, "room_count must be >= 2" if room_count < 2

    @rng = rng
    @room_ids = (1..room_count).map { |i| format("R%03d", i) }
    @edges = []
    @edge_keys = {}
    @adj = Hash.new { |h, k| h[k] = [] } # id => [[neighbor, kind], ...]
  end

  def add_edge(a, b, kind: nil)
    return false if a == b
    return false unless @room_ids.include?(a) && @room_ids.include?(b)

    e = Edge.new(a: a, b: b, kind: kind)
    k = e.key
    return false if @edge_keys[k]

    @edge_keys[k] = true
    @edges << e
    @adj[a] << [b, kind]
    @adj[b] << [a, kind]
    true
  end

  def degree(id)
    @adj[id].length
  end

  def neighbors(id)
    @adj[id].map(&:first)
  end

  def connected?
    start = @room_ids.first
    seen = {}
    stack = [start]
    seen[start] = true
    until stack.empty?
      cur = stack.pop
      @adj[cur].each do |(n, _kind)|
        next if seen[n]
        seen[n] = true
        stack << n
      end
    end
    seen.size == @room_ids.size
  end

  def random_room(excluding: nil)
    pool = excluding ? (@room_ids - Array(excluding)) : @room_ids
    pool[@rng.rand(pool.size)]
  end

  def random_pair
    a = random_room
    b = random_room(excluding: a)
    [a, b]
  end

  def to_h
    {
      "rooms" => @room_ids.map { |id| { "id" => id } },
      "edges" => @edges.map do |e|
        h = { "a" => e.a, "b" => e.b }
        h["kind"] = "vertical" if e.kind == :vertical
        h
      end
    }
  end
end

module MapGenerators
  module_function

  # -----------------------
  # Public generators
  # -----------------------

  # CITY CORE:
  # - 1 or 2 main "streets" as long paths
  # - branching spurs off streets
  # - a few cross links to create loops
  # - guaranteed min_leaf_rooms degree-1 rooms attached last
  def city_core(room_count: 35, main_streets: 2, spur_chance: 0.55, cross_links: 3, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    target1 = (room_count * 0.55).to_i.clamp(10, room_count - 1)
    path1 = build_path(g, core_ids, target_len: [target1, [core_ids.size, 2].max].min, rng: rng)

    if main_streets >= 2 && core_ids.size >= 6
      target2 = (room_count * 0.25).to_i.clamp(6, room_count - 1)
      path2 = build_path(g, core_ids, target_len: [target2, [core_ids.size, 2].max].min, rng: rng)
      g.add_edge(path2.first, path1[rng.rand(path1.size)], kind: nil) if path2.any? && path1.any?
    end

    anchors = g.room_ids.select { |id| g.degree(id) > 0 } - leaf_ids
    attach_spurs(g, core_ids, anchors: anchors, spur_chance: spur_chance, rng: rng)

    connect_isolated(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    add_random_cross_links_avoiding!(g, count: cross_links, avoid_ids: leaf_ids, rng: rng)

    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # DUNGEON MAZE STYLE:
  # - spanning tree on core rooms
  # - add extra edges for loops (avoids leaf rooms)
  # - attach leaf rooms at end
  def dungeon_maze(room_count: 35, extra_loops: 4, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    build_spanning_tree!(g, core_ids, rng: rng)

    add_random_cross_links_avoiding!(g, count: extra_loops, avoid_ids: leaf_ids, rng: rng)

    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # MULTI-LEVEL:
  # - generate base graph (city or dungeon) on core
  # - add vertical edges (avoids leaf rooms)
  # - encourage small clusters around the vertical endpoints
  # - attach leaf rooms last
  def multi_level(base: :dungeon, room_count: 35, vertical_edges: 2, cluster_size: 4, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    # Build base structure using only core ids
    case base
    when :city
      build_city_core_on_existing_graph!(g, core_ids, main_streets: 2, spur_chance: 0.55, cross_links: 3, leaf_ids: leaf_ids, rng: rng)
    else
      build_spanning_tree!(g, core_ids, rng: rng)
      add_random_cross_links_avoiding!(g, count: 4, avoid_ids: leaf_ids, rng: rng)
    end

    # Add vertical edges + mini-clusters, avoiding leaf ids
    pool = g.room_ids - leaf_ids
    vertical_edges.to_i.times do
      break if pool.size < 2
      a = pick_reasonable_anchor(g, candidates: pool, rng: rng)
      b = pool[rng.rand(pool.size)]
      b = pool[rng.rand(pool.size)] while b == a && pool.size > 1
      g.add_edge(a, b, kind: :vertical)

      cluster_size.to_i.times do
        x = b
        y = pool[rng.rand(pool.size)]
        next if y == x
        g.add_edge(x, y)
      end
    end

    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # HUB-AND-SPOKE:
  # - one hub with k spokes (paths)
  # - optional ring links between spokes for loops
  # - attach leaf rooms last
  def hub_and_spoke(room_count: 35, spokes: 6, spoke_len_range: (3..7), ring_links: 3, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    hub = core_ids.shift
    spoke_nodes = []

    spokes.to_i.times do
      break if core_ids.empty?
      first = core_ids.shift
      g.add_edge(hub, first)
      spoke_nodes << first

      len = rng.rand(spoke_len_range)
      cur = first
      (len - 1).times do
        break if core_ids.empty?
        nxt = core_ids.shift
        g.add_edge(cur, nxt)
        cur = nxt
      end
    end

    # Attach remaining core rooms as extra spurs off non-leaf nodes
    while core_ids.any?
      leaf = core_ids.shift
      anchor = pick_reasonable_anchor(g, candidates: (g.room_ids - leaf_ids), rng: rng)
      g.add_edge(anchor, leaf)
    end

    add_ring_links(g, spoke_nodes, ring_links: ring_links.to_i, rng: rng)

    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # BRANCHING RIVER:
  # - one main trunk path
  # - tributaries attach to trunk and sometimes fork
  # - shortcut links add loops
  # - attach leaf rooms last
  def branching_river(room_count: 35, trunk_ratio: 0.6, tributary_chance: 0.7, shortcut_links: 4, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    trunk_len = (room_count * trunk_ratio.to_f).to_i.clamp(10, room_count - 1)
    trunk_len = [trunk_len, [core_ids.size, 2].max].min
    trunk = build_path(g, core_ids, target_len: trunk_len, rng: rng)

    while core_ids.any?
      leaf = core_ids.shift
      attach = trunk[rng.rand(trunk.size)]
      g.add_edge(attach, leaf)

      while core_ids.any? && rng.rand < tributary_chance.to_f
        nxt = core_ids.shift
        g.add_edge(leaf, nxt)
        leaf = nxt

        if core_ids.any? && rng.rand < 0.25
          fork = core_ids.shift
          g.add_edge(leaf, fork)
        end
      end
    end

    add_random_cross_links_avoiding!(g, count: shortcut_links.to_i, avoid_ids: leaf_ids, rng: rng)
    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # LATTICE / GRID-ISH:
  # - build tree-ish base on core
  # - add extra links biased toward low-degree nodes (avoids leaf rooms)
  # - attach leaf rooms last
  def lattice(room_count: 35, loops: 8, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    build_spanning_tree!(g, core_ids, rng: rng)

    pool = g.room_ids - leaf_ids
    tries = 0
    added = 0
    loops = loops.to_i
    while added < loops && tries < loops * 60
      tries += 1

      sorted = pool.sort_by { |id| g.degree(id) }
      a = sorted.first([sorted.size, 12].min)[rng.rand([sorted.size, 12].min)]
      b = sorted.first([sorted.size, 12].min)[rng.rand([sorted.size, 12].min)]
      next if a == b
      next if g.neighbors(a).include?(b)
      next if g.degree(a) == 0 || g.degree(b) == 0

      added += 1 if g.add_edge(a, b)
    end

    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # CHAIN OF CLUSTERS:
  # - several mini-areas connected by chokepoints
  # - dense inside each cluster
  # - attach leaf rooms last
  def chain_of_clusters(room_count: 35, clusters: 4, intra_links: 2, min_leaf_rooms: 6, rng: Random.new)
    g = MapGraph.new(room_count: room_count, rng: rng)
    core_ids, leaf_ids = reserve_leaf_ids(g, min_leaf_rooms)

    clusters = clusters.to_i.clamp(2, [core_ids.size, 10].min)
    base = core_ids.size / clusters
    rem = core_ids.size % clusters
    cluster_sizes = Array.new(clusters, base)
    rem.times { |i| cluster_sizes[i] += 1 }

    cluster_rooms = cluster_sizes.map { |sz| core_ids.shift(sz) }

    cluster_rooms.each do |rooms|
      # Basic chain inside cluster to guarantee connectivity
      rooms.each_cons(2) { |a, b| g.add_edge(a, b) }

      # Add extra density
      intra_links.to_i.times do
        next if rooms.size < 2
        a = rooms[rng.rand(rooms.size)]
        b = rooms[rng.rand(rooms.size)]
        next if a == b
        g.add_edge(a, b)
      end
    end

    # Connect clusters in a chain
    (0...(cluster_rooms.size - 1)).each do |i|
      a = cluster_rooms[i][rng.rand(cluster_rooms[i].size)]
      b = cluster_rooms[i + 1][rng.rand(cluster_rooms[i + 1].size)]
      g.add_edge(a, b)
    end

    ensure_connected(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)

    attach_leaf_rooms!(g, leaf_ids, rng: rng)
    validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)

    g
  end

  # -----------------------
  # Helper building blocks
  # -----------------------

  def reserve_leaf_ids(g, min_leaf_rooms)
    min_leaf_rooms = min_leaf_rooms.to_i
    raise ArgumentError, "min_leaf_rooms must be >= 0" if min_leaf_rooms < 0
    raise ArgumentError, "min_leaf_rooms must be < room_count" if min_leaf_rooms >= g.room_ids.size

    ids = g.room_ids.dup
    leaf_ids = ids.pop(min_leaf_rooms)
    [ids, leaf_ids]
  end

  def validate_min_leaf_rooms!(g, leaf_ids, min_leaf_rooms)
    actual = leaf_ids.count { |id| g.degree(id) == 1 }
    return if actual >= min_leaf_rooms.to_i

    # Should not happen; if it does, force-fix by detaching extra edges (rare) or re-attaching.
    leaf_ids.each do |leaf|
      next if g.degree(leaf) == 1
      # We can't remove edges in this implementation; so we re-run a safer guarantee by ensuring
      # any non-degree-1 leaf gets an isolated "leaf buddy" is impossible without new rooms.
      # Raise loudly so you notice during testing.
      raise "Leaf guarantee failed for #{leaf}: degree=#{g.degree(leaf)}"
    end
  end

  def attach_leaf_rooms!(g, leaf_ids, rng:)
    eligible = g.room_ids - leaf_ids
    eligible = [g.room_ids.first] if eligible.empty?

    leaf_ids.each do |leaf|
      anchor = eligible[rng.rand(eligible.size)]
      g.add_edge(anchor, leaf)
    end
  end

  def build_path(g, remaining_ids, target_len:, rng:)
    return [] if remaining_ids.empty?

    start = remaining_ids.shift
    path = [start]
    while path.size < target_len && remaining_ids.any?
      nxt = remaining_ids.shift
      g.add_edge(path.last, nxt)
      path << nxt
    end
    path
  end

  def build_spanning_tree!(g, core_ids, rng:)
    raise ArgumentError, "Need at least 2 core rooms to build a tree" if core_ids.size < 2

    unseen = core_ids.dup
    tree = [unseen.shift]
    while unseen.any?
      from = tree[rng.rand(tree.size)]
      to = unseen.delete_at(rng.rand(unseen.size))
      g.add_edge(from, to)
      tree << to
    end
  end

  def attach_spurs(g, remaining_ids, anchors:, spur_chance:, rng:)
    return if remaining_ids.empty?

    anchors = anchors.dup
    anchors << g.room_ids.first if anchors.empty?

    while remaining_ids.any?
      break if rng.rand > spur_chance.to_f && g.connected? && remaining_ids.size < (g.room_ids.size * 0.15).to_i

      leaf = remaining_ids.shift
      anchor = anchors[rng.rand(anchors.size)]
      g.add_edge(anchor, leaf)
      anchors << leaf if rng.rand < 0.25
    end
  end

  def connect_isolated(g, eligible_ids:, rng:)
    isolated = eligible_ids.select { |id| g.degree(id) == 0 }
    return if isolated.empty?

    connected = eligible_ids.reject { |id| g.degree(id) == 0 }
    connected = [eligible_ids.first] if connected.empty?

    isolated.each do |id|
      anchor = connected[rng.rand(connected.size)]
      g.add_edge(anchor, id)
      connected << id
    end
  end

  def add_random_cross_links_avoiding!(g, count:, avoid_ids:, rng:)
    count = count.to_i
    return if count <= 0

    pool = g.room_ids - Array(avoid_ids)
    return if pool.size < 2

    tries = 0
    added = 0
    while added < count && tries < count * 50
      tries += 1
      a = pool[rng.rand(pool.size)]
      b = pool[rng.rand(pool.size)]
      next if a == b
      next if g.neighbors(a).include?(b)
      next if g.degree(a) == 0 || g.degree(b) == 0

      added += 1 if g.add_edge(a, b)
    end
  end

  def ensure_connected(g, eligible_ids: nil, rng:)
    eligible = eligible_ids ? Array(eligible_ids).uniq : g.room_ids
    return if eligible.size <= 1

    start = eligible.first
    main = bfs_set_restricted(g, start, eligible).to_a
    return if main.size == eligible.size

    rest = eligible - main

    while rest.any?
      comp_start = rest[rng.rand(rest.size)]
      comp = bfs_set_restricted(g, comp_start, eligible).to_a
      a = comp[rng.rand(comp.size)]
      b = main[rng.rand(main.size)]
      g.add_edge(a, b)
      main |= comp
      rest = eligible - main
    end
  end

  def bfs_set(g, start)
    seen = {}
    q = [start]
    seen[start] = true
    until q.empty?
      cur = q.shift
      g.neighbors(cur).each do |n|
        next if seen[n]
        seen[n] = true
        q << n
      end
    end
    seen.keys
  end

  def bfs_set_restricted(g, start, eligible)
    eligible_set =
      if eligible.is_a?(Hash)
        eligible
      else
        eligible.each_with_object({}) { |id, h| h[id] = true }
      end

    seen = {}
    q = [start]
    seen[start] = true

    until q.empty?
      cur = q.shift
      g.neighbors(cur).each do |n|
        next unless eligible_set[n]
        next if seen[n]
        seen[n] = true
        q << n
      end
    end

    seen.keys
  end

  def pick_reasonable_anchor(g, candidates:, rng:)
    candidates = Array(candidates)
    candidates = g.room_ids if candidates.empty?
    # Prefer higher-degree nodes to feel like hubs/doors/elevators
    candidates.max_by { |id| [g.degree(id), rng.rand] }
  end

  def add_ring_links(g, spoke_nodes, ring_links:, rng:)
    ring_links = ring_links.to_i
    return if ring_links <= 0
    return if spoke_nodes.size < 3

    tries = 0
    added = 0
    while added < ring_links && tries < ring_links * 60
      tries += 1
      i = rng.rand(spoke_nodes.size)
      j = (i + 1 + rng.rand(spoke_nodes.size - 1)) % spoke_nodes.size
      a = spoke_nodes[i]
      b = spoke_nodes[j]
      next if g.neighbors(a).include?(b)
      added += 1 if g.add_edge(a, b)
    end
  end

  # Used by multi_level city base to avoid instantiating nested generators
  def build_city_core_on_existing_graph!(g, core_ids, main_streets:, spur_chance:, cross_links:, leaf_ids:, rng:)
    target1 = (g.room_ids.size * 0.55).to_i.clamp(10, g.room_ids.size - 1)
    path1 = build_path(g, core_ids, target_len: [target1, [core_ids.size, 2].max].min, rng: rng)

    if main_streets.to_i >= 2 && core_ids.size >= 6
      target2 = (g.room_ids.size * 0.25).to_i.clamp(6, g.room_ids.size - 1)
      path2 = build_path(g, core_ids, target_len: [target2, [core_ids.size, 2].max].min, rng: rng)
      g.add_edge(path2.first, path1[rng.rand(path1.size)], kind: nil) if path2.any? && path1.any?
    end

    anchors = g.room_ids.select { |id| g.degree(id) > 0 } - leaf_ids
    attach_spurs(g, core_ids, anchors: anchors, spur_chance: spur_chance, rng: rng)
    connect_isolated(g, eligible_ids: (g.room_ids - leaf_ids), rng: rng)
    add_random_cross_links_avoiding!(g, count: cross_links, avoid_ids: leaf_ids, rng: rng)
    ensure_connected(g, rng: rng)
  end
end

# -----------------------
# Public API
# -----------------------
def generate_starfire_map(type: :dungeon_maze, room_count: 35, seed: nil, **opts)
  rng = seed ? Random.new(seed) : Random.new

  graph =
    case type
    when :city_core
      MapGenerators.city_core(room_count: room_count, rng: rng, **opts)
    when :dungeon_maze
      MapGenerators.dungeon_maze(room_count: room_count, rng: rng, **opts)
    when :multi_level_city
      MapGenerators.multi_level(base: :city, room_count: room_count, rng: rng, **opts)
    when :multi_level_dungeon
      MapGenerators.multi_level(base: :dungeon, room_count: room_count, rng: rng, **opts)
    when :hub_and_spoke
      MapGenerators.hub_and_spoke(room_count: room_count, rng: rng, **opts)
    when :branching_river
      MapGenerators.branching_river(room_count: room_count, rng: rng, **opts)
    when :lattice
      MapGenerators.lattice(room_count: room_count, rng: rng, **opts)
    when :chain_of_clusters
      MapGenerators.chain_of_clusters(room_count: room_count, rng: rng, **opts)
    else
      raise ArgumentError, "Unknown type: #{type}"
    end

  graph.to_h
end
