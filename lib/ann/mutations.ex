defmodule Mutations do
  import Genotype

  def link_from(from_neuron, to_id, generation)
  when is_record(from_neuron, Neuron) do
    {_, {from_layer, _}} = from_neuron.id
    {_, {to_layer, _}} = to_id

    if not List.member(from_neuron.output_ids, to_id) do
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
    if not List.member(from_sensor.output_ids, to_neuron_id) do
      output_ids = [to_neuron_id | from_sensor.output_ids]
      from_sensor.output_ids(output_ids)
                 .generation(generation)
    else
      raise "Already member"
    end
  end

  def link_to(from_id, to_neuron, vl, generation)
  when is_record(to_neuron, Neuron) do
    if not List.keymember(to_neuron.w_input_ids, 0, from_id) do
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
    if not List.member(to_actuator.input_ids, from_neuron_id) do
      input_ids = [from_neuron_id | to_actuator.input_ids]
      to_actuator.input_ids(input_ids)
                 .generation(generation)
    else
      raise "Already member!"
    end
  end

  def cut_link_from(from_neuron, to_id, generation)
  when is_record(from_neuron, Neuron) do
    if List.member(from_neuron.output_ids, to_id) do
      from_neuron.output_ids(from_neuron.output_ids -- [to_id])
                 .ro_ids(from_neuron.ro_ids -- [to_id])
                 .generation(generation)
    else
      raise "Not a member!"
    end
  end

  def cut_link_from(from_sensor, to_id, generation)
  when is_record(from_sensor, Sensor) do
    if List.member(from_sensor.output_ids, to_id) do
      from_sensor.output_ids(from_sensor.output_ids -- [to_id])
                 .generation(generation)
    else
      raise "Not a member!"
    end
  end

  def cut_link_to(from_id, to_neuron, generation)
  when is_record(to_neuron, Neuron) do
    if List.keymember(to_neuron.w_input_ids, 0, from_id) do
      w_input_ids = List.keydelete(to_neuron.w_input_ids, 0, from_id)
      to_neuron.w_input_ids(w_input_ids)
               .generation(generation)
    else
      raise "Not a member!" 
    end
  end

  def cut_link_to(from_id, to_actuator, generation)
  when is_record(to_actuator, Actuator) do
    if List.member(to_actuator.input_ids, from_id) do
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

  def mutate_weights(organism_id) do
    organism = Database.read(organism_id)
    monitor = Database.read(organism.monitor_id)

    neuron_id = pick(monitor.neuron_ids)
    neuron = Database.read(neuron_id)

    w_input_ids = Neuron.perturb_input(neuron.w_input_ids)
    history = [{:mutate_weights, neuron_id} | organism.history]

    new_neuron = neuron.w_input_ids(w_input_ids)
    new_organism = organism.history(history)

    Database.write(new_neuron)
    Database.write(new_organism)                            
  end
end
