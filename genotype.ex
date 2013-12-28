defmodule Genotype do
  import Enum

  defrecord Neuron, id: nil, monitor_id: nil, af: :tanh, w_input_ids: [], output_ids: []
  defrecord Sensor, id: nil, monitor_id: nil, f: nil, vl: [], output_ids: []
  defrecord Actuator, id: nil, monitor_id: nil, f: nil, vl: [], input_ids: []
  defrecord Monitor, id: nil, sensor_ids: [], actuator_ids: [], neuron_ids: []

  def create(sensor_fs, actuator_fs, hidden_layer_densities) do
    sensors = map(sensor_fs, &create_sensor/1) 
    actuators = map(actuator_fs, &create_actuator/1)

    sensor = first(sensors)
    actuator = first(actuators)

    output_vl = actuator.vl
    layer_densities = :lists.append(hidden_layer_densities, [output_vl])

    monitor_id = {:monitor, generate_id()}

    neurons = create_neuro_layers(monitor_id, sensor, actuator, layer_densities)

    neuron_ids = map(List.flatten(neurons), fn n -> n.id end)
    input_neuron_ids = map(first(neurons), fn n -> n.id end)
    output_neuron_ids = map(List.last(neurons), fn n -> n.id end)

    sensor = sensor.monitor_id(monitor_id).output_ids(input_neuron_ids)
    actuator = actuator.monitor_id(monitor_id).input_ids(output_neuron_ids)

    monitor = Monitor.new(id: monitor_id,
                          sensor_ids: [sensor.id],
                          actuator_ids: [actuator.id], 
                          neuron_ids: neuron_ids)
    genotype = List.flatten([monitor, sensor, actuator, neurons])
    genotype
  end

  def save(genotype, file_name) when is_list(genotype) do
    table_id = :ets.new(file_name, [:public, :set, {:keypos, 1}])
    map(genotype, fn x -> :ets.insert(table_id, x) end)
    :ets.tab2file(table_id, file_name)
  end

  def save(table_id, file_name) do
    :ets.tab2file(table_id, file_name)
  end

  def load(file_name) do
    {:ok, table_id} = :ets.file2tab(file_name)
    table_id
  end

  def read(table_id, key) do
    [r] = :ets.lookup(table_id, key)
    r
  end

  def write(table_id, r), do: :ets.insert(table_id, r)

  def print(file_name) do
    genotype = load(file_name)

    # Temp hack
    [monitor] = filter(:ets.tab2list(genotype), fn o ->
      case o.id do
        {:monitor, _} -> true
        _ ->  false
      end
    end)

    :io.format("~p~n", [monitor])
    map monitor.sensor_ids, fn id -> :io.format("~p~n", [read(genotype, id)]) end
    map monitor.neuron_ids, fn id -> :io.format("~p~n", [read(genotype, id)]) end
    map monitor.actuator_ids, fn id -> :io.format("~p~n", [read(genotype, id)]) end
  end

  def create_sensor(f) do
    case f do
      :rng -> Sensor.new(id: {:sensor, generate_id()}, f: :rng, vl: 2)
    end
  end

  def create_actuator(f) do
    case f do
      :pts -> Actuator.new(id: {:actuator, generate_id()}, f: :pts, vl: 1)
    end
  end

  def create_neuro_layers(monitor_id, sensor, actuator, layer_densities) do
    num_layers = length(layer_densities)
    [first_density | rest_densities] = layer_densities

    first_layer_inputs = [{sensor.id, sensor.vl}]
    first_neuron_ids = generate_ids(first_density)
                       |> map(fn id -> {:neuron, {1, id}} end)
                       
    {neurons, _} = zip(:lists.seq(1, num_layers), :lists.append(rest_densities, [nil]))
      |> map_reduce({first_layer_inputs, first_neuron_ids}, fn
        {^num_layers, nil}, {inputs, neuron_ids} ->
          outputs = [actuator.id]
          neurons = create_neuro_layer(monitor_id, inputs, neuron_ids, outputs)

          {neurons, nil}

        {layer, next_density}, {inputs, neuron_ids} ->
          # To create the neurons for the current layer, we need to
          # first generate IDs for the neurons of the next layer
          outputs = generate_ids(next_density) 
                    |> map(fn id -> {:neuron, {layer + 1, id}} end)

          neurons = create_neuro_layer(monitor_id, inputs, neuron_ids, outputs)

          # Information needed to create the next layer
          next_inputs = map(neuron_ids, fn id -> {id, 1} end)
          next_neuron_ids = outputs

          {neurons, {next_inputs, next_neuron_ids}}
      end)
    neurons
  end

  def create_neuro_layer(monitor_id, inputs, neuron_ids, outputs) do
    map neuron_ids, fn id ->
      create_neuron(id, monitor_id, inputs, outputs) 
    end
  end

  def create_neuron(id, monitor_id, inputs, outputs) do
    Neuron.new(id: id,
               monitor_id: monitor_id, 
               w_input_ids: create_neural_input(inputs),
               output_ids: outputs)
  end

  def create_neural_input(inputs) do
    map(inputs, fn {input_id, vl} ->
      weights = create_neural_weights(vl) 
      {input_id, weights}
    end)
    |> :lists.append([{:bias, :random.uniform() - 0.5}])
  end

  def create_neural_weights(vl) do
    map(:lists.seq(1, vl), fn _ -> :random.uniform() - 0.5 end)
  end

  def generate_id() do
    #{mega_s, s, micro_s} = :erlang.now()
    #1 / (mega_s * 1000000 + s + micro_s / 1000000)
    :erlang.phash2({:erlang.node(), :erlang.now()})
  end

  def generate_ids(n) do
    map(:lists.seq(1, n), fn _ -> generate_id() end)
  end
end
