defmodule TwoThousandFourtyEight do
  def get_tile(state, {x, y}) do
    if within_bounds(state, {x, y}) do
      Enum.at(state, y)
      |> Enum.at(x)
    else
      nil
    end
  end

  def update_tile(state, {x, y}, v) do
    row = Enum.at(state, y)
    new_row = List.replace_at(row, x, v)
    List.replace_at(state, y, new_row) 
  end

  defp is_available(state, pos), do: get_tile(state, pos) == nil

  defp direction_to_vector(:left), do: {-1, 0}
  defp direction_to_vector(:right), do: {1, 0}
  defp direction_to_vector(:up), do: {0, -1}
  defp direction_to_vector(:down), do: {0, 1}

  defp within_bounds(_, {x, y}), do: x >= 0 && x <= 3 && y >= 0 && y <= 3

  defp move_traversals(:left), do: {0..3, 0..3}
  defp move_traversals(:right), do: {3..0, 0..3}
  defp move_traversals(:up), do: {0..3, 0..3}
  defp move_traversals(:down), do: {0..3, 3..0}

  def free_positions(state) do
    Enum.reduce(Enum.with_index(state), [], fn({row, y}, ps) ->
      Enum.reduce(Enum.with_index(row), ps, fn
        {nil, x}, ps -> [{x, y} | ps]
        _, ps -> ps
      end)
    end)
  end

  defp rand_free_position(state) do
    xs = free_positions(state)
    :lists.nth(:random.uniform(length(xs)), xs)
  end
  
  defp add_random_tile(state) do
    pos = rand_free_position(state)
    val = if :random.uniform() < 0.9, do: 2, else: 4
    update_tile(state, pos, val)
  end

  def move(state, d) do
    v = direction_to_vector(d)
    {tx, ty} = move_traversals(d)
    t = lc x inlist Enum.to_list(tx), y inlist Enum.to_list(ty), do: {x, y}
    
    move_state =
      lc row inlist state do
        lc tile inlist row do
          if tile != nil, do: {tile, false},
                          else: nil
        end
      end

    #IO.inspect move_state

    {new_move_state, moved, score} = Enum.reduce(t, {move_state, false, 0}, fn({x, y}, {move_state, moved, score}) ->
      tile = get_tile(move_state, {x, y})

      if tile != nil do
        {tile_value, _} = tile
        {farthest_pos, next_pos} = find_farthest_position(move_state, {x, y}, v)
        next_tile = get_tile(move_state, next_pos)

        if next_tile != nil do
          {next_tile_value, next_tile_merged} = next_tile
          if next_tile_value == tile_value and next_pos != {x, y} and not next_tile_merged do # Merge 
            new_tile = {tile_value * 2, true}
          
            {move_state |> update_tile(next_pos, new_tile)
                        |> update_tile({x, y}, nil),
             true,
             score + tile_value * 2}
          else
            {move_state |> update_tile({x, y}, nil)
                        |> update_tile(farthest_pos, tile),
             moved or farthest_pos != {x, y}, 
             score} 
          end
        else
          {move_state |> update_tile({x, y}, nil)
                      |> update_tile(farthest_pos, tile),
           moved or farthest_pos != {x, y}, 
           score} 
        end
      else
        {move_state, moved, score}
      end
    end)

    new_state = lc row inlist new_move_state, do:
                (lc tile inlist row do
                   case tile do
                     nil -> nil
                     {value, _merged} -> value
                   end
                 end)

    new_state = if moved, do: add_random_tile(new_state),
                          else: new_state

    if moved do
      {new_state, score, moves_available(new_state)}
    else
      {new_state, score, true}
    end
  end

  def empty_state() do
    [[nil, nil, nil, nil],
     [nil, nil, nil, nil],
     [nil, nil, nil, nil],
     [nil, nil, nil, nil]]
  end

  def initial_state() do
    empty_state()
    |> add_random_tile
    |> add_random_tile 
  end

  def find_farthest_position(state, {x, y}=p, {vx, vy}=v) do
    find_farthest_position(state, {x+vx, y+vy}, v, p)
  end

  def find_farthest_position(state, {x, y}=p, {vx, vy}=v, prev) do
    if within_bounds(state, p) and is_available(state, p) do
      find_farthest_position(state, {x+vx, y+vy}, v, p)
    else
      {prev, p}
    end
  end

  def print(state) do
    lc row inlist state do
      lc tile inlist row do
        if tile != nil, do: :io.format("~5B |", [tile]),
                        else: IO.write("      |")
      end

      IO.puts("")
    end
  end

  def moves_available(state) do
    not Enum.empty?(free_positions(state)) or tile_merges_available(state)
  end

  def tile_merges_available(state) do
    t = lc x inlist Enum.to_list(0..3),
           y inlist Enum.to_list(0..3),
        do: {x, y}

    Enum.any? t, fn {x, y}=p ->
      tile = get_tile(state, p)
      if tile != nil do
        Enum.any? [:left, :right, :up, :down], fn dir ->
          {vx, vy} = direction_to_vector(dir)
          next_p = {x+vx, y+vy}
          next_tile = get_tile(state, next_p)

          next_tile != nil and next_tile == tile
        end
      else
        false
      end
    end
  end

  def test do
    test_loop(initial_state(), 0)
  end

  def test_loop(s, score) do
    print s
    IO.puts "Score: #{inspect score}"
    input = IO.gets("INPUT (wasd): ")
    {new_s, new_score, can_move} = case input do
      "w\n" -> move(s, :up)
      "a\n" -> move(s, :left)
      "s\n" -> move(s, :down)
      "d\n" -> move(s, :right)
      _ -> {s, 0, true}
    end
    if can_move, do: test_loop(new_s, score + new_score),
                 else: print new_s 
  end
end
