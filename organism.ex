defmodule Organism do
  import Genotype

  defrecord State, file_name: nil, genotype: nil, ids_to_pids: nil, monitor_pid: nil,
                   sensor_pids: nil, neuron_pids: nil, actuator_pids: nil, scape_pids: nil,
                   perturbed_neuron_pids: []

  def map(file_name) do
    genotype = Genotype.load(file_name)
    spawn_link(Organism, :map, [file_name, genotype])
  end

  def map(file_name, genotype) do
    {a, b, c} = :erlang.now()
    :random.seed(a, b, c)

    IO.puts "Organism begin #{inspect self}"

    ids_to_pids = :ets.new(:ids_to_pids, [:set, :private])

    # Temp hack
    [monitor] = Enum.filter(:ets.tab2list(genotype), fn o ->
      case o.id do
        {:monitor, _} -> true
        _ ->  false
      end
    end)

    scape_pids = spawn_scapes(ids_to_pids, genotype,
                              monitor.sensor_ids, monitor.actuator_ids)

    spawn_units(ids_to_pids, Monitor, [monitor.id])
    spawn_units(ids_to_pids, Sensor, monitor.sensor_ids)
    spawn_units(ids_to_pids, Actuator, monitor.actuator_ids)
    spawn_units(ids_to_pids, Neuron, monitor.neuron_ids)

    link_sensors(genotype, monitor.sensor_ids, ids_to_pids)
    link_neurons(genotype, monitor.neuron_ids, ids_to_pids)
    link_actuators(genotype, monitor.actuator_ids, ids_to_pids)

    {monitor_pid, sensor_pids,
     neuron_pids, actuator_pids} = link_monitor(monitor, ids_to_pids)

    monitor_pid = :ets.lookup_element(ids_to_pids, monitor.id, 2)

    loop(State.new(file_name: file_name,
                   genotype: genotype,
                   ids_to_pids: ids_to_pids,
                   monitor_pid: monitor_pid,
                   sensor_pids: sensor_pids,
                   neuron_pids: neuron_pids,
                   actuator_pids: actuator_pids,
                   scape_pids: scape_pids),
         0, 0, 0, 0, 1) 
  end

  def loop(s, highest_fitness, eval_acc, cycle_acc, time_acc, attempt) do
    monitor_pid = s.monitor_pid

    receive do
      # NN finished evaluation - did the fitness improve?
      {^monitor_pid, :completed, fitness, cycles, time} ->
        #IO.puts "Organism: new fitness: #{fitness}"

        {new_highest_fitness, new_attempt} = if fitness > highest_fitness do
          #IO.puts "Organism: backing up"
          
          # Yes! Leave the NN as it is.
          Enum.map s.neuron_pids, fn pid ->
            pid <- {self, :weights_backup}
          end

          {fitness, 0}
        else
          #IO.puts "Organism: restoring"

          # No. Restore perturbed neurons to previous weights
          Enum.map s.perturbed_neuron_pids, fn pid ->
            pid <- {self, :weights_restore}
          end

          {highest_fitness, attempt + 1}
        end

        # Continue training
        if new_attempt < 1000 do
          # Apply random perturbations to a random set of neurons
          num_neurons = length(s.neuron_pids)
          p = 1 / :math.sqrt(num_neurons)
          perturbed_neuron_pids = Enum.filter(s.neuron_pids, fn _ ->
            :random.uniform() < p end) 
          Enum.map perturbed_neuron_pids, fn pid ->
            pid <- {self, :weights_perturb}
          end

          #IO.puts "Organism: perturbed #{inspect perturbed_neuron_pids}"

          # Restart the NN
          s.monitor_pid <- {self, :reactivate}

          new_s = s.perturbed_neuron_pids perturbed_neuron_pids

          loop(s, new_highest_fitness, eval_acc + 1, cycle_acc + cycles,
               time_acc + time, new_attempt)
        else # Done training
          new_cycle_acc = cycle_acc + cycles
          new_time_acc = time_acc + time

          # Get updated weights from neurons and save
          new_weights = Monitor.get_state(s.neuron_pids, [])
          update_genotype(s.ids_to_pids, s.genotype, new_weights)
          Genotype.save(s.genotype, s.file_name)

          s.monitor_pid <- {self, :terminate}
          Enum.map s.scape_pids, fn pid -> pid <- {self, :terminate} end

          IO.puts "Organism finished training: Fitness: #{inspect new_highest_fitness}, num cycles: #{new_cycle_acc}, time: #{inspect new_time_acc}, num evals: #{eval_acc}"

          Process.whereis(:trainer) <- {self, highest_fitness, eval_acc, cycle_acc, time_acc}
        end
    end
  end

  def spawn_units(ids_to_pids, type, ids) do
    Enum.map ids, fn id ->
      pid = type.create(self)
      :ets.insert(ids_to_pids, {id, pid})
      :ets.insert(ids_to_pids, {pid, id})
    end
  end

  def link_sensors(genotype, [id | ids], ids_to_pids) do
    r = Genotype.read(genotype, id)

    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    output_pids = Enum.map r.output_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    scape_pid = :ets.lookup_element(ids_to_pids, r.scape, 2)

    pid <- {self, {r.id, monitor_pid, r.f, scape_pid, r.vl, output_pids}}

    link_sensors(genotype, ids, ids_to_pids)
  end
  def link_sensors(_, [], _), do: :ok

  def link_actuators(genotype, [id | ids], ids_to_pids) do
    r = Genotype.read(genotype, id)

    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    input_pids = Enum.map r.input_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    scape_pid = :ets.lookup_element(ids_to_pids, r.scape, 2)

    pid <- {self, {r.id, monitor_pid, r.f, scape_pid, input_pids}}

    link_actuators(genotype, ids, ids_to_pids)
  end
  def link_actuators(_, [], _), do: :ok

  def link_neurons(genotype, [id | ids], ids_to_pids) do
    r = Genotype.read(genotype, id)

    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    output_pids = Enum.map r.output_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    w_input_pids = Enum.map r.w_input_ids, fn
      {:bias, bias} -> {:bias, bias}
      {id, weights} -> {:ets.lookup_element(ids_to_pids, id, 2), weights}
    end
    #IO.inspect w_input_pids
    
    pid <- {self, {r.id, monitor_pid, r.af, w_input_pids, output_pids}}
    
    link_neurons(genotype, ids, ids_to_pids)
  end
  def link_neurons(_, [], _), do: :ok

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

    pid <- {self, monitor.id, sensor_pids, actuator_pids, neuron_pids}

    {pid, sensor_pids, neuron_pids, actuator_pids}
  end

  def update_genotype(ids_to_pids, genotype, weights) do
    Enum.map weights, fn {id, w_input_pids} ->
      w_input_ids = Enum.map w_input_pids, fn
        {:bias, bias} -> {:bias, bias}
        {pid, w} -> {:ets.lookup_element(ids_to_pids, pid, 2), w}
      end

      n = Genotype.read(genotype, id)
      new_n = n.w_input_ids(w_input_ids)

      Genotype.write(genotype, new_n)
    end

    #  Enum.reduce weights, genotype, fn {id, w_input_pids}, acc ->
    #    n = List.keyfind(acc, id, 1)
    #    w_input_ids = Enum.map w_input_pids, fn
    #      {:bias, bias} -> {:bias, bias}
    #      {pid, w} -> {:ets.lookup_element(ids_to_pids, pid, 2), w}
    #    end

    #    new_n = n.w_input_ids(w_input_ids)

    #    List.keyreplace(acc, id, 1, new_n)
    #  end
  end

  def spawn_scapes(ids_to_pids, genotype, sensor_ids, actuator_ids) do
    sensor_scapes = Enum.map(sensor_ids, fn id ->
      Genotype.read(genotype, id).scape end)
    actuator_scapes = Enum.map(actuator_ids, fn id ->
      Genotype.read(genotype, id).scape end)
    scapes = sensor_scapes ++ (actuator_scapes -- sensor_scapes)

    scape_pids_names = Enum.map scapes, fn
      {:private, name} ->
        #IO.puts "Creating scape #{name}"
        {Scape.create(self), {:private, name}}
    end

    Enum.map scape_pids_names, fn {pid, name} ->
        :ets.insert(ids_to_pids, {name, pid})
        :ets.insert(ids_to_pids, {pid, name})

        pid <- {self, name}
    end

    Enum.map scape_pids_names, fn {pid, name} -> pid end
  end
end
