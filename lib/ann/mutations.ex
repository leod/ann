defmodule Mutations do
  import Genotype

  def mutators, do:
    [:mutate_weights,
     :add_bias,
     :remove_bias,
     :add_neuron_outlink,
     :add_neuron_inlink,
     :add_sensor_outlink,
     :add_actuator_inlink,
     :outsplice,
     :add_sensor,
     :add_actuator]

  def mutate(organism_id) do
    :random.seed(:erlang.now())
    
    :mnesia.transaction fn ->
      Database.update(organism_id, fn o -> o.generation(o.generation + 1) end)
      apply_mutators(organism_id) 
    end
  end

  def apply_mutators(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    num_neurons = length(monitor.neuron_ids)
    num_mutations = :math.pow(num_neurons, 0.5)
                    |> :erlang.round
                    |> :random.uniform
                    |> :erlang.round

    IO.puts "Number of neurons: #{num_neurons}, performing #{num_mutations} on #{inspect organism_id}"

    apply_mutators(organism_id, num_mutations)
  end

  def apply_mutators(_, 0), do: :ok

  def apply_mutators(organism_id, i) do
    result = :mnesia.transaction fn ->
      mutator = pick(mutators)
      IO.puts "Mutator #{inspect mutator}"

      apply(Mutations, mutator, [organism_id])
    end

    case result do
      {:atomic, _} ->
        apply_mutators(organism_id, i-1)
      error ->
        IO.puts "Error: #{inspect error}, reapplying mutation"
        apply_mutators(organism_id, i)
    end
  end

  # Mutation functions
  def mutate_weights(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    #IO.inspect neuron.w_input_ids
    #IO.inspect neuron
    w_input_ids = Neuron.perturb_input(neuron.w_input_ids)
    history = [{:mutate_weights, neuron_id} | organism.history]

    neuron.w_input_ids(w_input_ids) |> Database.write
    organism.history(history) |> Database.write
  end

  def add_bias(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    if not List.keymember?(neuron.w_input_ids, :bias, 0) do
      bias = {:bias, :random.uniform() - 0.5}
      neuron.w_input_ids(neuron.w_input_ids ++ [bias])
            .generation(organism.generation)
      |> Database.write

      history = [{:add_bias, neuron_id} | organism.history]
      organism.history(history) |> Database.write
    else
      exit("Already has bias!")
    end
  end

  def remove_bias(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    if List.keymember?(neuron.w_input_ids, :bias, 0) do
      w_input_ids = List.keydelete(neuron.w_input_ids, :bias, 0)
      neuron.w_input_ids(w_input_ids)
            .generation(organism.generation)
      |> Database.write

      history = [{:remove_bias, neuron_id} | organism.history]
      organism.history(history) |> Database.write
    else
      exit("Already has bias!")
    end
  end

  def mutate_af(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    afs = organism.constraint.neural_afs -- [neuron.af]
    new_af = Genotype.generate_neuron_af(afs)
    neuron.af(new_af) |> Database.write

    history = [{:mutate_af, neuron_id} | organism.history]
    organism.history(history) |> Database.write
  end

  def add_neuron_inlink(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    [input_ids, _] = List.unzip(neuron.w_input_ids)
    case (monitor.neuron_ids ++ monitor.sensor_ids) -- input_ids do
      [] ->
        exit("Neuron already fully connected!")
      ids ->
        do_link(organism_id, pick(ids), neuron_id)

        history = [{:add_neuron_inlink, neuron_id} | organism.history]
        organism.history(history) |> Database.write
    end 
  end 

  def add_neuron_outlink(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    case (monitor.neuron_ids ++ monitor.actuator_ids) -- neuron.output_ids do
      [] ->
        exit("Neuron already fully connected!")
      ids ->
        do_link(organism_id, neuron_id, pick(ids))

        history = [{:add_neuron_outlink, neuron_id} | organism.history]
        organism.history(history) |> Database.write
    end 
  end

  def add_sensor_outlink(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)
    
    sensor_id = pick(monitor.sensor_ids)
    sensor = Database.read(sensor_id)

    case monitor.neuron_ids -- sensor.output_ids do
      [] ->
        exit("Sensor already fully connected!" )
      ids ->
        do_link(organism_id, sensor_id, pick(ids))

        history = [{:add_sensor_outlink, sensor_id} | organism.history]
        organism.history(history) |> Database.write
    end
  end

  def add_actuator_inlink(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)
    
    actuator_id = pick(monitor.actuator_ids)
    actuator = Database.read(actuator_id)

    case monitor.neuron_ids -- actuator.input_ids do
      [] ->
        exit("Sensor already fully connected!" )
      ids ->
        do_link(organism_id, pick(ids), actuator_id)

        history = [{:add_actuator_inlink, actuator_id} | organism.history]
        organism.history(history) |> Database.write
    end
  end

  def add_neuron(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    {target_layer, target_neuron_ids} = pick(organism.pattern)
    new_neuron_id = {Genotype.Neuron, {target_layer, Genotype.generate_id()}}
    Genotype.generate_neuron(new_neuron_id, monitor.id, organism.generation,
                             organism.constraint, [], [])
    |> Database.write
    
    from_id = pick(monitor.neuron_ids ++ monitor.sensor_ids)
    do_link(organism_id, from_id, new_neuron_id)
    to_id = pick(monitor.neuron_ids ++ monitor.actuator_ids)
    do_link(organism_id, new_neuron_id, to_id)

    history = [{:add_neuron, new_neuron_id, from_id, to_id} | organism.history] 
    pattern = List.keyreplace(organism.pattern, target_layer, 0,
                              [new_neuron_id | target_neuron_ids])
    organism.history(history)
            .pattern(pattern) |> Database.write
    monitor.neuron_ids([new_neuron_id | monitor.neuron_ids])
    |> Database.write
  end

  # Insert a new random inbetween two randomly chosen neurons.
  # Creates a new layer between the two neurons if necessary.
  def outsplice(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    #{Neuron, {layer, _}} = neuron_id = pick(monitor.neuron_ids)
    neuron_id = pick(monitor.neuron_ids)
    {Genotype.Neuron, {layer, _}} = neuron_id
    neuron = Database.read(neuron_id)
    pool_output_ids = lc target_id={_, {target_layer, _}} inlist neuron.output_ids,
                         target_layer > layer,
                         do: target_id
    if pool_output_ids == [], do:
      exit("Empty output pool")
    {_, {output_layer, _}} = output_id = pick(pool_output_ids)

    new_layer = get_splice_layer(organism.pattern, layer, output_layer, :next)
    new_neuron_id = {Genotype.Neuron, {new_layer, Genotype.generate_id()}}
    Genotype.generate_neuron(new_neuron_id, organism.monitor_id, organism.generation,
                             organism.constraint, [], [])
    |> Database.write

    pattern = if List.keymember?(organism.pattern, new_layer, 0) do
      # Insert neuron into existing layer
      {new_layer, neuron_ids} = List.keyfind(organism.pattern, new_layer, 0)
      List.keyreplace(organism.pattern, new_layer, 0,
                      {new_layer, [new_neuron_id | neuron_ids]})
    else
      # Insert new layer
      Enum.sort([{new_layer, [new_neuron_id]} | organism.pattern])
    end

    do_cut_link(organism_id, neuron_id, output_id)
    do_link(organism_id, neuron_id, new_neuron_id)
    do_link(organism_id, new_neuron_id, output_id)

    history = [{:outsplice, neuron_id, new_neuron_id, output_id} | organism.history]
    organism.history(history).pattern(pattern) |> Database.write
    monitor.neuron_ids([new_neuron_id | monitor.neuron_ids]) |> Database.write
  end

  def add_sensor(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)
    
    used_sensors = Enum.map monitor.sensor_ids, fn id ->
      Database.read(id)
        .id(nil).monitor_id(nil).output_ids([]).generation(0)
    end
    pool_sensors = Morphology.get_sensors(organism.constraint.morphology)
                   -- used_sensors
    if pool_sensors == [], do:
      exit("All sensors already used!")

    new_sensor_id = {Genotype.Sensor, {-1, Genotype.generate_id()}}
    pick(pool_sensors).id(new_sensor_id)
                      .monitor_id(organism.monitor_id)
    |> Database.write
    
    neuron_id = pick(monitor.neuron_ids)
    do_link(organism_id, new_sensor_id, neuron_id)
    
    history = [{:add_sensor, new_sensor_id, neuron_id} | organism.history]
    organism.history(history) |> Database.write
    monitor.sensor_ids([new_sensor_id | monitor.sensor_ids]) |> Database.write
  end 

  def add_actuator(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)
  
    used_actuators = Enum.map monitor.actuator_ids, fn id ->
      Database.read(id)
        .id(nil).monitor_id(nil).input_ids([]).generation(0)
    end
    pool_actuators = Morphology.get_actuators(organism.constraint.morphology)
                     -- used_actuators
    if pool_actuators == [], do:
      exit("All actuators already used!")

    new_actuator_id = {Genotype.Actuator, {-1, Genotype.generate_id()}}
    pick(pool_actuators).id(new_actuator_id)
                        .monitor_id(organism.monitor_id)
    |> Database.write
    
    neuron_id = pick(monitor.neuron_ids)
    do_link(organism_id, neuron_id, new_actuator_id)
    
    history = [{:add_actuator, new_actuator_id, neuron_id} | organism.history]
    organism.history(history) |> Database.write
    monitor.actuator_ids([new_actuator_id | monitor.actuator_ids]) |> Database.write
  end

  # Utility functions:
  def get_splice_layer(pattern, from_layer, to_layer, :next) do
    get_next_layer(pattern, from_layer, to_layer)
  end
  #def get_new_layer(from_layer, to_layer, pattern, :previous) do
    #get_next_layer(from_layer, to_layer, pattern)
  #end

  def get_next_layer([{from_layer, _}], from_layer, 1), do:
    (from_layer + 1) / 2

  def get_next_layer([{from_layer, _} | pattern], from_layer, to_layer) do
    {next_layer, _} = Enum.first(pattern)
    if next_layer == to_layer, do: (from_layer + to_layer) / 2 ,
                               else: next_layer
  end
  def get_next_layer([_ | pattern], from_layer, to_layer), do:
    get_next_layer(pattern, from_layer, to_layer) 

  def link_from(from_neuron, to_id, generation)
  when is_record(from_neuron, Genotype.Neuron) do
    {_, {from_layer, _}} = from_neuron.id
    {_, {to_layer, _}} = to_id

    if not Enum.member?(from_neuron.output_ids, to_id) do
      ro_ids = if from_layer >= to_layer do
        [to_id | from_neuron.ro_ids]
      else
        from_neuron.ro_ids
      end

      output_ids = [to_id | from_neuron.output_ids]
      from_neuron.output_ids(output_ids)
                 .ro_ids(ro_ids)
                 .generation(generation)
    else
      exit("Already member")
    end
  end

  def link_from(from_sensor, to_neuron_id, generation)
  when is_record(from_sensor, Genotype.Sensor) do
    if not Enum.member?(from_sensor.output_ids, to_neuron_id) do
      output_ids = [to_neuron_id | from_sensor.output_ids]
      from_sensor.output_ids(output_ids)
                 .generation(generation)
    else
      exit("Already member")
    end
  end

  def link_to(from_id, to_neuron, vl, generation)
  when is_record(to_neuron, Genotype.Neuron) do
    if not List.keymember?(to_neuron.w_input_ids, from_id, 0) do
      weights = generate_neural_weights(vl)
      w_input_ids = [{from_id, weights} | to_neuron.w_input_ids]

      to_neuron.w_input_ids(w_input_ids)
               .generation(generation)
    else
      exit("Already member")
    end
  end

  def link_to(from_neuron_id, to_actuator, 1, generation)
  when is_record(to_actuator, Genotype.Actuator) do
    if not Enum.member?(to_actuator.input_ids, from_neuron_id) do
      input_ids = [from_neuron_id | to_actuator.input_ids]
      to_actuator.input_ids(input_ids)
                 .generation(generation)
    else
      exit("Already member!")
    end
  end

  def cut_link_from(from_neuron, to_id, generation)
  when is_record(from_neuron, Genotype.Neuron) do
    if Enum.member?(from_neuron.output_ids, to_id) do
      from_neuron.output_ids(from_neuron.output_ids -- [to_id])
                 .ro_ids(from_neuron.ro_ids -- [to_id])
                 .generation(generation)
    else
      exit("Not a member!")
    end
  end

  def cut_link_from(from_sensor, to_id, generation)
  when is_record(from_sensor, Genotype.Sensor) do
    if Enum.member?(from_sensor.output_ids, to_id) do
      from_sensor.output_ids(from_sensor.output_ids -- [to_id])
                 .generation(generation)
    else
      exit("Not a member!")
    end
  end

  def cut_link_to(from_id, to_neuron, generation)
  when is_record(to_neuron, Genotype.Neuron) do
    if List.keymember?(to_neuron.w_input_ids, from_id, 0) do
      w_input_ids = List.keydelete(to_neuron.w_input_ids, from_id, 0)
      to_neuron.w_input_ids(w_input_ids)
               .generation(generation)
    else
      exit("Not a member!" )
    end
  end

  def cut_link_to(from_id, to_actuator, generation)
  when is_record(to_actuator, Genotype.Actuator) do
    if Enum.member?(to_actuator.input_ids, from_id) do
      to_actuator.input_ids(to_actuator.input_ids -- [from_id])
                 .generation(generation)
    else
      exit("Not a member!")
    end
  end

  def do_link(organism_id, from_id, to_id) do
    organism = Database.read(organism_id)

    from = Database.update from_id, &link_from(&1, to_id, organism.generation)
    vl = cond do
      is_record(from, Genotype.Neuron) -> 1
      is_record(from, Genotype.Sensor) -> from.vl
    end

    Database.update to_id, &link_to(from_id, &1, vl, organism.generation)
  end

  def do_cut_link(organism_id, from_id, to_id) do
    organism = Database.read(organism_id)

    Database.update from_id, &cut_link_from(&1, to_id, organism.generation)
    Database.update to_id, &cut_link_to(from_id, &1, organism.generation)
  end

  def pick(xs) when is_list(xs) do
    :lists.nth(:random.uniform(length(xs)), xs)
  end
end
