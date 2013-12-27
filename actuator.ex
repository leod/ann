defmodule Actuator do
  def create(mapper_pid) do
    spawn(Actuator, :loop, [mapper_pid])
  end

  def loop(mapper_pid) do
    IO.puts "Actuator begin #{inspect self}"

    receive do
      {^mapper_pid, {id, monitor_pid, f, input_pids}} ->
        loop(id, monitor_pid, f, input_pids, input_pids, [])
    end
  end

  def loop(id, monitor_pid, f, [input_pid | input_pids], all_input_pids, acc) do
    receive do
      {^input_pid, :forward, input} ->
        loop(id, monitor_pid, f, input_pids, all_input_pids, :lists.append(input, acc))

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def loop(id, monitor_pid, f, [], all_input_pids, acc) do
    #Actuator.f(Enum.reverse(acc))
    case f do
      :pts -> pts(Enum.reverse(acc))
    end

    monitor_pid <- {self, :sync}
    loop(id, monitor_pid, f, all_input_pids, all_input_pids, [])
  end

  def pts(result) do
    :io.format("Actuator result: ~p~n", [result])
  end
end
