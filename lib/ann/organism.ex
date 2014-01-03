defmodule Organism do
  import Genotype

  @max_attempts 100

  defrecord State, organism_id: nil, population_pid: nil, ids_to_pids: nil,
                   monitor_pid: nil, sensor_pids: nil, neuron_pids: nil,
                   actuator_pids: nil, scape_pids: nil,
                   perturbed_neuron_pids: []

  def start(organism_id, population_pid, mode // :train) do
    spawn(Organism, :init, [organism_id, population_pid, mode])
  end

  def init(organism_id, population_pid, mode) do
    :random.seed(:erlang.now())

    #IO.puts "Organism begin #{inspect self}, id #{inspect organism_id}"

    ids_to_pids = :ets.new(:ids_to_pids, [:set, :private])

    result = Database.transaction fn ->
      organism = Database.read(organism_id)
      monitor = Database.read(organism.monitor_id)

      scape_pids = spawn_scapes(ids_to_pids, monitor.sensor_ids,
                                monitor.actuator_ids)
      spawn_units(ids_to_pids, Monitor, [monitor.id])
      spawn_units(ids_to_pids, Sensor, monitor.sensor_ids)
      spawn_units(ids_to_pids, Actuator, monitor.actuator_ids)
      spawn_units(ids_to_pids, Neuron, monitor.neuron_ids)

      if mode == :trace do # Tell actuators to print output to console
        Enum.map monitor.actuator_ids, fn id ->
          :ets.lookup_element(ids_to_pids, id, 2) <- {self, :enable_trace}
        end
      end

      link_sensors(monitor.sensor_ids, ids_to_pids)
      link_neurons(monitor.neuron_ids, ids_to_pids)
      link_actuators(monitor.actuator_ids, ids_to_pids)

      {scape_pids, link_monitor(monitor, ids_to_pids)}
    end

    case result do
      {:atomic, {scape_pids,
                 {monitor_pid, sensor_pids, neuron_pids, actuator_pids}}} ->
        state = State.new(organism_id: organism_id,
                          population_pid: population_pid,
                          ids_to_pids: ids_to_pids,
                          monitor_pid: monitor_pid,
                          sensor_pids: sensor_pids,
                          neuron_pids: neuron_pids,
                          actuator_pids: actuator_pids,
                          scape_pids: scape_pids)
        case mode do
          :train -> loop_train(state, 0, 0, 0, 0, 1) 
          :trace -> loop_trace(state)
        end
      error ->
        IO.puts "Failed to create organism #{inspect organism_id}: #{inspect error}"
        # TODO: Clean up started processes?
    end
  end

  def loop_trace(s) do
    monitor_pid = s.monitor_pid

    receive do
      {^monitor_pid, :completed, fitness, cycles, time} ->
        IO.puts "Evaluation finished: Fitness #{fitness}, cycles #{cycles}, time #{time}"
    end
  end

  def loop_train(s, highest_fitness, eval_acc, cycle_acc, time_acc, attempt) do
    monitor_pid = s.monitor_pid

    receive do
      # NN finished evaluation - did the fitness improve?
      {^monitor_pid, :completed, fitness, cycles, time} ->
        #IO.puts "Organism: new fitness: #{fitness}"

        {new_highest_fitness, new_attempt} = if fitness > highest_fitness do
          Enum.map s.neuron_pids, fn pid ->
            pid <- {self, :weights_backup}
          end

          {fitness, 0}
        else
          # No. Restore perturbed neurons to previous weights
          Enum.map s.perturbed_neuron_pids, fn pid ->
            pid <- {self, :weights_restore}
          end

          {highest_fitness, attempt + 1}
        end

        # Reactivate network
        Enum.map s.neuron_pids, fn pid -> pid <- {self, :prepare_reactivate} end
        gather_ready(length(s.neuron_pids))

        # Continue training
        if new_attempt < @max_attempts do
          # Apply random perturbations to a random set of neurons
          num_neurons = length(s.neuron_pids)
          p = 1 / :math.sqrt(num_neurons)
          perturbed_neuron_pids = Enum.filter(s.neuron_pids, fn _ ->
            :random.uniform() < p end) 
          Enum.map perturbed_neuron_pids, fn pid ->
            pid <- {self, :weights_perturb}
          end

          # Restart the NN
          Enum.map s.neuron_pids, fn pid ->
            pid <- {self, :reactivate}
          end
          s.monitor_pid <- {self, :reactivate}
          #IO.puts "Reactivated"

          new_s = s.perturbed_neuron_pids perturbed_neuron_pids

          loop_train(new_s, new_highest_fitness, eval_acc + 1,
                    cycle_acc + cycles, time_acc + time, new_attempt)
        else # Done training
          new_cycle_acc = cycle_acc + cycles
          new_time_acc = time_acc + time


          # Debugging
          #Enum.map s.neuron_pids, fn pid -> pid <- {self, :reactivate} end
          #Enum.map s.actuator_pids, fn pid -> pid <- {self, :enable_trace} end
          #s.monitor_pid <- {self, :reactivate}
          #receive do {^monitor_pid, :completed, _, _, _} -> :ok end
          #Enum.map s.neuron_pids, fn pid -> pid <- {self, :prepare_reactivate} end
          #gather_ready(length(s.neuron_pids))

          # Get updated weights from neurons and save
          Enum.map s.neuron_pids, fn pid -> pid <- {self, :reactivate} end
          new_weights = Monitor.get_state(s.neuron_pids, [])
          Database.transaction fn ->
            update_genotype(s.ids_to_pids, new_weights)
          end

          # Terminate
          s.monitor_pid <- {self, :terminate}
          Enum.map s.scape_pids, fn pid -> pid <- {self, :terminate} end

          #IO.puts "Organism finished training: Fitness: #{inspect new_highest_fitness}, num cycles: #{new_cycle_acc}, time: #{inspect new_time_acc}, num evals: #{eval_acc}"

          if s.population_pid != nil do
            :gen_server.cast(s.population_pid,
                             {s.organism_id, :terminated, new_highest_fitness,
                              eval_acc, new_cycle_acc, new_time_acc})
          end

          :ets.delete(s.ids_to_pids)
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

  def link_sensors([id | ids], ids_to_pids) do
    r = Database.read(id)

    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    output_pids = Enum.map r.output_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    scape_pid = :ets.lookup_element(ids_to_pids, r.scape, 2)

    pid <- {self, {r.id, monitor_pid, r.f, scape_pid, r.vl, output_pids}}

    link_sensors(ids, ids_to_pids)
  end
  def link_sensors([], _), do: :ok

  def link_actuators([id | ids], ids_to_pids) do
    r = Database.read(id)

    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    input_pids = Enum.map r.input_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    scape_pid = :ets.lookup_element(ids_to_pids, r.scape, 2)

    pid <- {self, {r.id, monitor_pid, r.f, scape_pid, input_pids}}

    link_actuators(ids, ids_to_pids)
  end
  def link_actuators([], _), do: :ok

  def link_neurons([id | ids], ids_to_pids) do
    r = Database.read(id)

    sensor_w_input_ids = Enum.filter r.w_input_ids, fn
      {{Genotype.Sensor, _}, _} -> true
      _ -> false
    end
    neuron_w_input_ids = Enum.reduce(sensor_w_input_ids, r.w_input_ids,
                                     &(List.delete(&2, &1)))
    sorted_w_input_ids = sensor_w_input_ids ++ neuron_w_input_ids

    pid = :ets.lookup_element(ids_to_pids, r.id, 2)
    monitor_pid = :ets.lookup_element(ids_to_pids, r.monitor_id, 2)
    output_pids = Enum.map r.output_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    w_input_pids = Enum.map(sorted_w_input_ids, fn
      {:bias, bias} -> {:bias, bias}
      {id, weights} -> {:ets.lookup_element(ids_to_pids, id, 2), weights}
    end)
    ro_pids = Enum.map r.ro_ids, fn id ->
      :ets.lookup_element(ids_to_pids, id, 2)
    end
    
    pid <- {self, {r.id, monitor_pid, r.af, w_input_pids, output_pids, ro_pids}}
    
    link_neurons(ids, ids_to_pids)
  end
  def link_neurons([], _), do: :ok

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

  def update_genotype(ids_to_pids, weights) do
    Enum.map weights, fn {id, w_input_pids} ->
      w_input_ids = Enum.map w_input_pids, fn
        {:bias, bias} -> {:bias, bias}
        {pid, w} -> {:ets.lookup_element(ids_to_pids, pid, 2), w}
      end

      n = Database.read(id)
      new_n = n.w_input_ids(w_input_ids)

      Database.write(new_n)
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

  def spawn_scapes(ids_to_pids, sensor_ids, actuator_ids) do
    sensor_scapes = Enum.map(sensor_ids, fn id ->
      Database.read(id).scape end)
    actuator_scapes = Enum.map(actuator_ids, fn id ->
      Database.read(id).scape end)
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

  def gather_ready(0), do: :ok
  def gather_ready(n) do
    receive do
      {_, :ready} -> gather_ready(n-1)
      after 100000 ->
        IO.puts "Not all readys received #{n}"
    end
  end

  def reactivate_neurons(state) do

  end
end
