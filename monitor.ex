defmodule Monitor do
  import Enum

  defrecord State, id: nil, organism_pid: nil, sensor_pids: nil, actuator_pids: nil, neuron_pids: nil

  def create(organism_pid) do
    spawn(Monitor, :start, [organism_pid])
  end

  def start(organism_pid) do
    IO.puts "Monitor begin #{inspect self}"

    receive do
      {^organism_pid, {id, sensor_pids, actuator_pids, neuron_pids}, num_steps} ->
        map sensor_pids, fn pid ->
          pid <- {self, :sync}
        end
        loop(State.new(id: id,
                       organism_pid: organism_pid,
                       sensor_pids: sensor_pids,
                       actuator_pids: actuator_pids,
                       neuron_pids: neuron_pids),
             actuator_pids,
             num_steps)
    end
  end

  def loop(s, _actuator_pids, 0) do
    weights = get_state(s.neuron_pids, [])
    s.organism_pid <- {self, :save, weights}
    terminate([s.sensor_pids, s.actuator_pids, s.neuron_pids])
  end

  def loop(s, [actuator_pid | actuator_pids], step) do
    receive do
      {^actuator_pid, :sync} ->
        loop(s, actuator_pids, step)
    end
  end

  def loop(s, [], step) do
    map s.sensor_pids, fn pid ->
      pid <- {self, :sync}
    end 

    loop(s, s.actuator_pids, step - 1)
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
