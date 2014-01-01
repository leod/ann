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

  def read(key) do
    [r] = :mnesia.read({elem(key, 0), key})
    r
  end

  def write(rs) when is_list(rs), do: Enum.map(rs, fn r -> write(r) end)
  def write(r) do
    :mnesia.write(r)
  end

  def update(key, f) do
    v = read(key)
    write(f.(v))
  end

  def delete(key), do: :mnesia.delete({elem(key, 0), key})

  def print(organism_id) do
    organism = read(organism_id)
    monitor = read(organism.monitor_id)

    IO.inspect organism
    IO.inspect monitor
    map monitor.sensor_ids, fn id -> IO.inspect id; IO.inspect(read(id)) end
    map monitor.neuron_ids, fn id -> IO.inspect(read(id)) end
    map monitor.actuator_ids, fn id -> IO.inspect(read(id)) end
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
                             :output_ids],
                    Genotype.Sensor, monitor.sensor_ids)
      clone_records(id_map, [:id,
                             :w_input_ids,
                             :output_ids,
                             :ro_ids],
                    Genotype.Neuron, monitor.neuron_ids)
      clone_records(id_map, [:id,
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

  def create_test_organism() do
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
end
