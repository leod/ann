defmodule Monitor do
  import Enum

  def create(mapper_pid) do
    spawn(Monitor, :loop, [mapper_pid])
  end

  def loop(mapper_pid) do
    IO.puts "Monitor begin #{inspect self}"

    receive do
      {^mapper_pid, {id, sensor_pids, actuator_pids, neuron_pids}, num_steps} ->
        map sensor_pids, fn pid ->
          pid <- {self, :sync}
        end
        loop(id, mapper_pid, sensor_pids, actuator_pids,
             actuator_pids, neuron_pids, num_steps)
    end
  end

  def loop(id, mapper_pid, sensor_pids, actuator_pids,
            all_actuator_pids, neuron_pids, 0) do
    weights = get_state(neuron_pids, [])
    mapper_pid <- {self, :save, weights}
    terminate([sensor_pids, all_actuator_pids, neuron_pids])
  end

  def loop(id, mapper_pid, sensor_pids, [actuator_pid | actuator_pids],
            all_actuator_pids, neuron_pids, step) do
    receive do
      {^actuator_pid, :sync} ->
        loop(id, mapper_pid, sensor_pids, actuator_pids,
             all_actuator_pids, neuron_pids, step)
    end
  end

  def loop(id, mapper_pid, sensor_pids, [], all_actuator_pids,
            neuron_pids, step) do
    map sensor_pids, fn pid ->
      pid <- {self, :sync}
    end 

    loop(id, mapper_pid, sensor_pids, all_actuator_pids,
         all_actuator_pids, neuron_pids, step - 1)
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
