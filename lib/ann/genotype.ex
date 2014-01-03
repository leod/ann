defmodule Genotype do
  import Enum

  defrecord Sensor, id: nil,
                    monitor_id: nil,
                    generation: 0,
                    f: nil,
                    scape: nil,
                    vl: [],
                    output_ids: []
  defrecord Neuron, id: nil,
                    generation: 0,
                    monitor_id: nil,
                    af: :tanh,
                    w_input_ids: [],
                    output_ids: [],
                    ro_ids: []
  defrecord Actuator, id: nil,
                      monitor_id: nil,
                      generation: 0,
                      f: nil,
                      scape: nil,
                      vl: [],
                      input_ids: []
  defrecord Monitor, id: nil,
                     sensor_ids: [],
                     actuator_ids: [],
                     neuron_ids: []
  defrecord Organism, id: nil,
                      generation: 0,
                      population_id: nil,
                      species_id: nil,
                      monitor_id: nil,
                      fingerprint: nil,
                      constraint: nil,
                      history: [],
                      fitness: 0,
                      innovation_factor: 0,
                      pattern: []
  defrecord Species, id: nil,
                     platform_id: nil,
                     organism_ids: [],
                     champion_ids: [],
                     morphologies: [],
                     innovation_factor: 0,
                     fitness: 0
  defrecord Constraint, morphology: [],
                        neural_afs: []
  defrecord Population, id: nil,
                        platform_id: nil,
                        species_ids: [],
                        morphologies: [],
                        innovation_factor: 0

  def is_id({type, _}, type), do: true
  def is_id(_, _), do: false

  def generate(organism_id, species_id, species_constraint) do
    :random.seed(:erlang.now())

    monitor_id = {Monitor, {:origin, generate_id()}}

    morphology = species_constraint.morphology
    sensors = map Morphology.get_init_sensors(morphology), fn s ->
      s.id({Sensor, {-1, generate_id()}})
       .monitor_id(monitor_id)
    end
    actuators = map Morphology.get_init_actuators(morphology), fn a ->
      a.id({Actuator, {1, generate_id()}})
       .monitor_id(monitor_id)
    end

    {sensors, neurons, actuators} =
      generate_initial_neuro_layer(monitor_id,
                                   0,
                                   species_constraint,
                                   sensors,
                                   actuators)

    sensor_ids = map sensors, fn s -> s.id end
    neuron_ids = map neurons, fn n -> n.id end
    actuator_ids = map actuators, fn a -> a.id end

    monitor = Monitor.new(id: monitor_id,
                          organism_id: organism_id,
                          sensor_ids: sensor_ids,
                          neuron_ids: neuron_ids,
                          actuator_ids: actuator_ids)

    organism = Organism.new(id: organism_id,
                            monitor_id: monitor_id,
                            species_id: species_id,
                            constraint: species_constraint,
                            pattern: [{0, neuron_ids}])

    organism = organism.fingerprint(calculate_fingerprint(organism,
                                                          monitor,
                                                          sensors,
                                                          actuators))

    [organism, monitor, sensors, neurons, actuators]
  end

  def generate_initial_neuro_layer(monitor_id, generation, constraint,
                                   sensors, actuators) do
    {res_actuators, {res_sensors, res_neurons}} =
    map_reduce actuators, {sensors, []}, fn actuator, {sensors, neurons} ->
      neuron_ids = map generate_ids(actuator.vl), fn id -> {Neuron, {0, id}} end

      {add_neurons, new_sensors} =
        generate_initial_neurons(monitor_id, generation, constraint,
                                 neuron_ids, sensors, actuator)

      new_actuator = actuator.input_ids(neuron_ids)

      {new_actuator, {new_sensors, add_neurons ++ neurons}}
    end

    {res_sensors, res_neurons, res_actuators}
  end
                                   
  def generate_initial_neurons(monitor_id, generation, constraint,
                               neuron_ids, sensors, actuator) do
    map_reduce neuron_ids, sensors, fn neuron_id, sensors ->
      {inputs, new_sensors} = if :random.uniform() >= 0.5 do
        # Connect just one sensor to this neuron
        sensor = :lists.nth(:random.uniform(length(sensors)), sensors)

        inputs = [{sensor.id, sensor.vl}]
        new_sensor = sensor.output_ids([neuron_id | sensor.output_ids])
        new_sensors = List.keyreplace(sensors, sensor.id, 1, new_sensor)
        
        {inputs, new_sensors}
      else
        # Connect all sensors to this neuron
        inputs = map sensors, fn s -> {s.id, s.vl} end
        new_sensors = map sensors, fn s ->
          s.output_ids([neuron_id | s.output_ids])
        end

        {inputs, new_sensors}
      end

      neuron = generate_neuron(neuron_id, monitor_id, generation, constraint,
                               inputs, [actuator.id])
      {neuron, new_sensors}
    end
  end

  def generate_sensor(f) do
    case f do
      :rng -> Sensor.new(id: {:sensor, generate_id()}, f: :rng, vl: 2)
    end
  end

  def generate_actuator(f) do
    case f do
      :pts -> Actuator.new(id: {:actuator, generate_id()}, f: :pts, vl: 1)
    end
  end

  def generate_neuron(id, monitor_id, generation, constraint, inputs, outputs) do
    Neuron.new(id: id,
               monitor_id: monitor_id, 
               generation: generation,
               af: generate_neuron_af(constraint.neural_afs),
               w_input_ids: generate_neural_input(inputs),
               output_ids: outputs)
  end

  def generate_neuron_af(afs) do
    case afs do
      [] -> :tanh
      x -> :lists.nth(:random.uniform(length(x)), x)
    end
  end

  def generate_neural_input(inputs) do
    map(inputs, fn {input_id, vl} ->
      weights = generate_neural_weights(vl) 
      {input_id, weights}
    end)
    |> :lists.append([{:bias, :random.uniform() - 0.5}])
  end

  def generate_neural_weights(vl) do
    map(1 .. vl, fn _ -> :random.uniform() - 0.5 end)
  end

  def calculate_fingerprint(organism, monitor, sensors, actuators) do
    general_pattern = map organism.pattern, fn {layer_index, neuron_ids} ->
      {layer_index, length(neuron_ids)}
    end
    general_history = generalize_history(organism.history)
    general_sensors = map sensors, fn s -> s.id(nil).monitor_id(nil) end
    general_actuators = map actuators, fn a -> a.id(nil).monitor_id(nil) end

    {general_pattern, general_history, general_sensors, general_actuators}
  end

  def generalize_history(history) do
    IO.puts "TODO generalize_history"
    history
  end


  def generate_id() do
    #{mega_s, s, micro_s} = :erlang.now()
    #1 / (mega_s * 1000000 + s + micro_s / 1000000)
    :erlang.phash2({:erlang.node(), :erlang.now()})
  end

  def generate_ids(n) do
    map(1 .. n, fn _ -> generate_id() end)
  end

  # Random morphologies, will be moved somewhere else at some point
  def xor_mimic(:sensors) do
    [Sensor.new(id: {:sensor, generate_id()},
                f: :xor_get_input,
                scape: {:private, :xor_sim},
                vl: 2)]
  end

  def xor_mimic(:actuators) do
    [Actuator.new(id: {:actuator, generate_id()},
                  f: :xor_send_output,
                  scape: {:private, :xor_sim},
                  vl: 1)]
  end

  # Currently unused
  def generate_neuro_layers(monitor_id, constraint, sensor, actuator,
                            layer_densities) do
    num_layers = length(layer_densities)
    [first_density | rest_densities] = layer_densities

    first_layer_inputs = [{sensor.id, sensor.vl}]
    first_neuron_ids = generate_ids(first_density)
                       |> map(fn id -> {:neuron, {1, id}} end)
                       
    {neurons, _} = zip(1 .. num_layers, rest_densities ++ [nil])
      |> map_reduce({first_layer_inputs, first_neuron_ids}, fn
        {^num_layers, nil}, {inputs, neuron_ids} ->
          outputs = [actuator.id]
          neurons = generate_neuro_layer(monitor_id, constraint, inputs,
                                         neuron_ids, outputs)

          {neurons, nil}

        {layer, next_density}, {inputs, neuron_ids} ->
          # To create the neurons for the current layer, we need to
          # first generate IDs for the neurons of the next layer
          outputs = generate_ids(next_density) 
                    |> map(fn id -> {:neuron, {layer + 1, id}} end)

          neurons = generate_neuro_layer(monitor_id, constraint, inputs,
                                         neuron_ids, outputs)

          # Information needed to create the next layer
          next_inputs = map(neuron_ids, fn id -> {id, 1} end)
          next_neuron_ids = outputs

          {neurons, {next_inputs, next_neuron_ids}}
      end)
    neurons
  end

  def generate_neuro_layer(monitor_id, constraint, inputs, neuron_ids, outputs) do
    map neuron_ids, fn id ->
      generate_neuron(id, monitor_id, 0, constraint, inputs, outputs) 
    end
  end
end
