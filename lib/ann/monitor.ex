defmodule Monitor do
  import Enum

  defrecord State, id: nil, organism_pid: nil,
                   sensor_pids: nil, actuator_pids: nil, neuron_pids: nil

  def create(organism_pid) do
    spawn(Monitor, :start, [organism_pid])
  end

  def start(organism_pid) do
    #IO.puts "Monitor begin #{inspect self}"

    receive do
      {^organism_pid, id, sensor_pids, actuator_pids, neuron_pids} ->
        map sensor_pids, fn pid ->
          pid <- {self, :sync}
        end
        loop(State.new(id: id,
                       organism_pid: organism_pid,
                       sensor_pids: sensor_pids,
                       actuator_pids: actuator_pids,
                       neuron_pids: neuron_pids),
             actuator_pids,
             1, 0, 0, :erlang.now(), :active)
    end
  end

  def loop(s, [actuator_pid | actuator_pids], cycle_acc, fitness_acc,
           halt_flag_acc, start_time, :active) do
    organism_pid = s.organism_pid

    receive do
      {actuator_pid, :sync, fitness, halt_flag} ->
        loop(s, actuator_pids, cycle_acc, fitness_acc + fitness,
             halt_flag_acc + halt_flag, start_time, :active)

      {^organism_pid, :terminate} ->
        #IO.puts "Monitor terminating"
        terminate([s.sensor_pids, s.neuron_pids, s.actuator_pids])
    end
  end

  def loop(s, [], cycle_acc, fitness_acc, halt_flag_acc, start_time, :active) do
    if halt_flag_acc > 0 do
      time_diff = :timer.now_diff(:erlang.now(), start_time)
      s.organism_pid <- {self, :completed, fitness_acc, cycle_acc, time_diff}

      loop(s, s.actuator_pids, cycle_acc, fitness_acc, halt_flag_acc, start_time, :inactive)
    else
      map s.sensor_pids, fn pid ->
        pid <- {self, :sync}
      end

      loop(s, s.actuator_pids, cycle_acc + 1, fitness_acc, halt_flag_acc, start_time, :active)
    end
  end

  def loop(s, _, _, _, _, _, :inactive) do
    organism_pid = s.organism_pid

    receive do
      {^organism_pid, :reactivate} ->
        start_time = :erlang.now()
        map s.sensor_pids, fn pid ->
          pid <- {self, :sync}
        end

        #IO.puts "Monitor reactivated"
        loop(s, s.actuator_pids, 1, 0, 0, start_time, :active)

      {^organism_pid, :terminate} ->
        #IO.puts "Monitor terminating"
        terminate([s.sensor_pids, s.neuron_pids, s.actuator_pids])
    end
  end

  def get_state([neuron_pid | neuron_pids], acc) do
    neuron_pid <- {self, :get_state}
    receive do
      {^neuron_pid, neuron_id, weights} ->
        get_state(neuron_pids, [{neuron_id, weights} | acc])
    end
  end

  def get_state([], acc), do: acc

  def terminate(pids) do
    map List.flatten(pids), fn pid ->
      pid <- {self, :terminate}
    end
  end
end
