defmodule Mutations do
  import Genotype

  def mutate_weights(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

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

    IO.inspect neuron.w_input_ids
    if not List.keymember?(neuron.w_input_ids, :bias, 0) do
      bias = {:bias, [:random.uniform() - 0.5]}
      neuron.w_input_ids(neuron.w_input_ids ++ [bias])
            .generation(organism.generation)
      |> Database.write

      history = [{:add_bias, neuron_id} | organism.history]
      organism.history(history) |> Database.write
    else
      raise "Already has bias!"
    end
  end

  def remove_bias(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)
    IO.inspect neuron

    if List.keymember?(neuron.w_input_ids, :bias, 0) do
      w_input_ids = List.keydelete(neuron.w_input_ids, :bias, 0)
      neuron.w_input_ids(w_input_ids)
            .generation(organism.generation)
      |> Database.write

      history = [{:remove_bias, neuron_id} | organism.history]
      organism.history(history) |> Database.write
    else
      raise "Already has bias!"
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

    {input_ids, _} = List.unzip(neuron.w_input_ids)
    case (monitor.neuron_ids ++ monitor.sensor_ids) -- input_ids do
      [] ->
        raise "Neuron already fully connected!"
      ids ->
        do_link(organism, pick(ids), neuron_id)

        history = [{:add_neuron_inlink, neuron_id} | organism.history]
        organism.history(history) |> Database.write
    end 
  end 

  def add_neuron_outlink(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    {input_ids, _} = List.unzip(neuron.w_input_ids)
    case (monitor.neuron_ids ++ monitor.actuator_ids) -- input_ids do
      [] ->
        raise "Neuron already fully connected!"
      ids ->
        do_link(organism, neuron_id, pick(ids))

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
        raise "Sensor already fully connected!" 
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
        raise "Sensor already fully connected!" 
      ids ->
        do_link(organism_id, pick(ids), actuator_id)

        history = [{:add_actuator_inlink, actuator_id} | organism.history]
        organism.history(history) |> Database.write
    end
  end

  # Utility functions:
 
  def link_from(from_neuron, to_id, generation)
  when is_record(from_neuron, Neuron) do
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
      raise "Already member"
    end
  end

  def link_from(from_sensor, to_neuron_id, generation)
  when is_record(from_sensor, Sensor) do
    if not Enum.member?(from_sensor.output_ids, to_neuron_id) do
      output_ids = [to_neuron_id | from_sensor.output_ids]
      from_sensor.output_ids(output_ids)
                 .generation(generation)
    else
      raise "Already member"
    end
  end

  def link_to(from_id, to_neuron, vl, generation)
  when is_record(to_neuron, Neuron) do
    if not List.keymember?(to_neuron.w_input_ids, from_id, 0) do
      weights = generate_neural_weights(vl)
      w_input_ids = [{from_id, weights} | to_neuron.w_input_ids]

      to_neuron.w_input_ids(w_input_ids)
               .generation(generation)
    else
      raise "Already member"
    end
  end

  def link_to(from_neuron_id, to_actuator, generation)
  when is_record(to_actuator, Actuator) do
    if not Enum.member?(to_actuator.input_ids, from_neuron_id) do
      input_ids = [from_neuron_id | to_actuator.input_ids]
      to_actuator.input_ids(input_ids)
                 .generation(generation)
    else
      raise "Already member!"
    end
  end

  def cut_link_from(from_neuron, to_id, generation)
  when is_record(from_neuron, Neuron) do
    if Enum.member?(from_neuron.output_ids, to_id) do
      from_neuron.output_ids(from_neuron.output_ids -- [to_id])
                 .ro_ids(from_neuron.ro_ids -- [to_id])
                 .generation(generation)
    else
      raise "Not a member!"
    end
  end

  def cut_link_from(from_sensor, to_id, generation)
  when is_record(from_sensor, Sensor) do
    if Enum.member?(from_sensor.output_ids, to_id) do
      from_sensor.output_ids(from_sensor.output_ids -- [to_id])
                 .generation(generation)
    else
      raise "Not a member!"
    end
  end

  def cut_link_to(from_id, to_neuron, generation)
  when is_record(to_neuron, Neuron) do
    if List.keymember?(to_neuron.w_input_ids, from_id, 0) do
      w_input_ids = List.keydelete(to_neuron.w_input_ids, from_id, 0)
      to_neuron.w_input_ids(w_input_ids)
               .generation(generation)
    else
      raise "Not a member!" 
    end
  end

  def cut_link_to(from_id, to_actuator, generation)
  when is_record(to_actuator, Actuator) do
    if Enum.member?(to_actuator.input_ids, from_id) do
      to_actuator.input_ids(to_actuator.input_ids ++ [from_id])
                 .generation(generation)
    else
      raise "Not a member!"
    end
  end

  def do_link(organism_id, from_id, to_id) do
    organism = Database.read(organism_id)

    from = Database.update from_id, &link_from(&1, to_id, organism.generation)
    vl = cond do
      is_record(from, Neuron) -> 1
      is_record(from, Sensor) -> from.vl
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
