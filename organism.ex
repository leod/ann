defmodule Organism do
  import Genotype

  def map(file_name) do
    {:ok, genotype} = :file.consult(file_name)

    spawn_link(Organism, :map, [file_name, genotype])
  end

  def map(file_name, genotype) do
    ids_to_pids = :ets.new(:ids_to_pids, [:set, :private])

    [monitor | units] = genotype

    spawn_units(ids_to_pids, Monitor, [monitor.id])
    spawn_units(ids_to_pids, Sensor, monitor.sensor_ids)
    spawn_units(ids_to_pids, Actuator, monitor.actuator_ids)
    spawn_units(ids_to_pids, Neuron, monitor.neuron_ids)

    link_units(units, ids_to_pids)
    link_monitor(monitor, ids_to_pids)

    monitor_pid = :ets.lookup_element(ids_to_pids, monitor.id, 2)

    receive do
      {^monitor_pid, :save, weights} ->
        genotype = update_genotype(ids_to_pids, genotype, weights)
        #save_genotype(genotype, file_name)

        IO.puts "Updated to file #{file_name}"
    end
  end

  def spawn_units(ids_to_pids, type, ids) do
    Enum.map ids, fn id ->
      pid = type.create(self)
      :ets.insert(ids_to_pids, {id, pid})
      :ets.insert(ids_to_pids, {pid, id})
    end
  end

  def link_units([r | rs], ids_to_pids) when is_record(r, Genotype.Sensor) do
    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    output_pids = Enum.map r.output_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end

    pid <- {self, {r.id, monitor_pid, r.f, r.vl, output_pids}}

    link_units(rs, ids_to_pids)
  end

  def link_units([r | rs], ids_to_pids) when is_record(r, Genotype.Actuator) do
    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    input_pids = Enum.map r.input_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end

    pid <- {self, {r.id, monitor_pid, r.f, input_pids}}

    link_units(rs, ids_to_pids)
  end

  def link_units([r | rs], ids_to_pids) when is_record(r, Genotype.Neuron) do
    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    output_pids = Enum.map r.output_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    w_input_pids = Enum.map r.w_input_ids, fn
      {:bias, bias} -> {:bias, bias}
      {id, weights} -> {:ets.lookup_element(ids_to_pids, id, 2), weights}
    end
    
    pid <- {self, {r.id, monitor_pid, r.af, w_input_pids, output_pids}}
    
    link_units(rs, ids_to_pids)
  end

  def link_units([], _), do: :ok

  def link_monitor(monitor, ids_to_pids) do
    pid = :ets.lookup_element(ids_to_pids, monitor.id, 2)
    sensor_pids = Enum.map monitor.sensor_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    actuator_pids = Enum.map monitor.actuator_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    neuron_pids = Enum.map monitor.neuron_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end

    pid <- {self, {monitor.id, sensor_pids, actuator_pids, neuron_pids}, 10}
  end

  def update_genotype(ids_to_pids, genotype, weights) do
    Enum.reduce weights, genotype, fn {id, w_input_pids}, acc ->
      n = List.keyfind(acc, id, 1)
      w_input_ids = Enum.map w_input_pids, fn
        {:bias, bias} -> {:bias, bias}
        {pid, w} -> {:ets.lookup_element(ids_to_pids, pid, 2), w}
      end

      new_n = n.w_input_ids(w_input_ids)

      List.keyreplace(acc, id, 1, new_n)
    end
  end
end
