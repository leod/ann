defmodule Database do
  import Enum

  def start() do
    :mnesia.start
  end

  def create() do
    params = fn type ->
      attributes = map type.__record__(:fields), fn {name, _} -> name end
      [{:disc_copies, [node]},
       {:type, :set},
       {:attributes, attributes}]
    end

    :mnesia.create_schema([node])
    :mnesia.start
    :mnesia.create_table(Genotype.Sensor, params.(Genotype.Sensor))
    :mnesia.create_table(Genotype.Neuron, params.(Genotype.Neuron))
    :mnesia.create_table(Genotype.Actuator, params.(Genotype.Actuator))
    :mnesia.create_table(Genotype.Monitor, params.(Genotype.Monitor))
    :mnesia.create_table(Genotype.Organism, params.(Genotype.Organism))
    :mnesia.create_table(Genotype.Species, params.(Genotype.Species))
    :mnesia.create_table(Genotype.Population, params.(Genotype.Population))
  end

  def reset() do
    :mnesia.stop
    :mnesia.delete_schema([node])
    create
  end

  def try_read(key) do
    case :mnesia.read({elem(key, 0), key}) do
      [r] -> r
      _ -> nil
    end
  end

  def dirty_read(key) do
    [r] = :mnesia.dirty_read({elem(key, 0), key})
    r
  end

  def read(key) do
    [r] = :mnesia.read({elem(key, 0), key})
    r
  end

  def transaction(f) do
    :mnesia.transaction f
  end

  def write(rs) when is_list(rs), do: Enum.map(rs, fn r -> write(r) end)
  def write(r) do
    :mnesia.write(r)
  end

  def update(key, f) do
    v = read(key)
    new_v = f.(v)
    write(new_v)
    new_v 
  end

  def delete(key), do: :mnesia.delete({elem(key, 0), key})

  def print(organism_id) do
    :mnesia.transaction fn ->
      organism = read(organism_id)
      monitor = read(organism.monitor_id)

      IO.inspect organism
      IO.inspect monitor
      map monitor.sensor_ids, fn id -> IO.inspect id; IO.inspect(read(id)) end
      map monitor.neuron_ids, fn id -> IO.inspect(read(id)) end
      map monitor.actuator_ids, fn id -> IO.inspect(read(id)) end
    end
  end

  def delete_organism(organism_id) do
    :mnesia.transaction fn ->
      organism = read(organism_id)
      monitor = read(organism.monitor_id)

      map monitor.sensor_ids, fn id -> delete(id) end
      map monitor.neuron_ids, fn id -> delete(id) end
      map monitor.actuator_ids, fn id -> delete(id) end

      delete(organism.monitor_id)
      delete(organism.id)
    end
  end

  def delete_species(species_id) do
    map Database.read(species_id).organism_ids, &delete_organism(&1)
    delete(species_id)
  end
  
  def delete_population(population_id) do
    IO.inspect Database.read(population_id).species_ids
    IO.inspect Database.read(Enum.first(Database.read(population_id).species_ids))
    map Database.read(population_id).species_ids, &delete_species(&1)
    delete(population_id)
  end

  def clone_organism(organism_id) do
    clone_organism_id = {Genotype.Organism, Genotype.generate_id()}
    {:atomic, _} = clone_organism(organism_id, clone_organism_id)
    clone_organism_id
  end

  def clone_organism(organism_id, clone_organism_id) do
    :mnesia.transaction fn ->
      id_map = :ets.new(:id_map, [:set, :private])

      map_ids = fn ids ->
        map ids, fn {type, {layer_index, num}} ->
          clone_id = {type, {layer_index, Genotype.generate_id()}}  
          :ets.insert(id_map, {{type, {layer_index, num}}, clone_id})
          
          clone_id
        end
      end

      organism = read(organism_id)
      monitor = read(organism.monitor_id)

      :ets.insert(id_map, {organism_id, clone_organism_id})

      [clone_monitor_id] = map_ids.([organism.monitor_id])
      clone_sensor_ids = map_ids.(monitor.sensor_ids)
      clone_neuron_ids = map_ids.(monitor.neuron_ids)
      clone_actuator_ids = map_ids.(monitor.actuator_ids)

      clone_records(id_map, [:id,
                             :monitor_id,
                             :output_ids],
                    Genotype.Sensor, monitor.sensor_ids)
      clone_records(id_map, [:id,
                             :monitor_id,
                             :w_input_ids,
                             :output_ids,
                             :ro_ids],
                    Genotype.Neuron, monitor.neuron_ids)
      clone_records(id_map, [:id,
                             :monitor_id,
                             :input_ids],
                    Genotype.Actuator, monitor.actuator_ids)
      write(monitor.id(clone_monitor_id)
                   .sensor_ids(clone_sensor_ids)
                   .actuator_ids(clone_actuator_ids)
                   .neuron_ids(clone_neuron_ids))
      write(organism.id(clone_organism_id)
                    .monitor_id(clone_monitor_id))
    end
  end

  def clone_records(id_map, fields, type, [r_id | r_ids]) do
    r = read(r_id) 

    clone_r = reduce fields, r, fn field, r ->
      value = apply(type, field, [r])
      clone_value = cond do
        is_list(value) ->
          map value, fn
            {:bias, w} ->
              {:bias, w}

            {id, ws} when is_list(ws) ->
              {:ets.lookup_element(id_map, id, 2), ws}

            id ->
              :ets.lookup_element(id_map, id, 2)
          end

        true ->
          :ets.lookup_element(id_map, value, 2)
      end

      apply(type, field, [clone_value, r])
    end

    write(clone_r)

    clone_records(id_map, fields, type, r_ids)
  end

  def clone_records(_, _, _, []), do: :ok

  def test() do
    organism_id = {Genotype.Organism, :test}
    clone_organism_id = {Genotype.Organism, :test_clone}
    species_id = {Genotype.Species, :test_species}
    species_constraint = Genotype.Constraint.new

    :mnesia.transaction fn ->
      Genotype.generate(organism_id, species_id, species_constraint)
      |> write

      clone_organism(organism_id, clone_organism_id)

      print(organism_id)
      print(clone_organism_id)

      delete_organism(organism_id)
      delete_organism(clone_organism_id)
    end
  end

  def create_test() do
    :mnesia.transaction fn ->
      organism_id = {Genotype.Organism, :test}
      species_id = {Genotype.Species, :test_species}
      species_constraint = Genotype.Constraint.new

      if try_read(organism_id) != nil, do: delete_organism(organism_id)

      Genotype.generate(organism_id, species_id, species_constraint)
      |> write

      print(organism_id)
    end
  end

  def print_test() do
    start()

    :mnesia.transaction fn ->
      print({Genotype.Organism, :test})
    end 
  end

  def organism_to_dot(organism_id, file_name) do
    id_dot = fn id -> "\"#{inspect id}\"" end
    monitor_dot = fn monitor ->
      "#{id_dot.(monitor.id)} [label=\"Monitor\", shape=box]\n"
    end
    label_dot = fn
      {Genotype.Neuron, id} -> "N#{inspect id}"
      {Genotype.Sensor, id} -> "S#{inspect id}"
      {Genotype.Actuator, id} -> "A#{inspect id}"
    end
    w_inputs_dot = fn to_id, inputs ->
      map(inputs, fn
        {:bias, _} -> ""
        {from_id, weights} ->
          "#{id_dot.(from_id)} -> #{id_dot.(to_id)} [label=\"#{inspect weights}\"]\n"
      end)
      |> reduce("", &(&1 <> &2))
    end
    inputs_dot = fn to_id, inputs ->
      map(inputs, fn from_id ->
        "#{id_dot.(from_id)} -> #{id_dot.(to_id)}\n"
      end)
      |> reduce("", &(&1 <> &2))
    end
    neuron_dot = fn neuron ->
      "#{id_dot.(neuron.id)} [label=\"#{label_dot.(neuron.id)}\" shape=circle]\n"
      <> w_inputs_dot.(neuron.id, neuron.w_input_ids)
    end
    sensor_dot = fn sensor ->
      "#{id_dot.(sensor.id)} [label=\"#{label_dot.(sensor.id)}\" shape=trapezium]\n"
    end
    actuator_dot = fn actuator ->
      "#{id_dot.(actuator.id)} [label=\"#{label_dot.(actuator.id)}\" shape=trapezium]\n"
      <> inputs_dot.(actuator.id, actuator.input_ids)
    end

    {:atomic, dot} = transaction fn ->
      organism = read(organism_id)
      monitor = read(organism.monitor_id)

      n_dots = map(monitor.neuron_ids, &(Database.read(&1) |> neuron_dot.()))
               |> reduce("", &(&1 <> &2))
      s_dots = map(monitor.sensor_ids, &(Database.read(&1) |> sensor_dot.()))
               |> reduce("", &(&1 <> &2))
      a_dots = map(monitor.actuator_ids, &(Database.read(&1) |> actuator_dot.()))
               |> reduce("", &(&1 <> &2))

      prefix_dot = "digraph #{id_dot.(organism.id)} {\n"
      postfix_dot = "}\n"

      dot = prefix_dot
            #<> monitor_dot.(monitor)
            <> n_dots <> s_dots <> a_dots
            <> postfix_dot
    end

    File.write!(file_name, dot)
  end
end
