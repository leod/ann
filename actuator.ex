defmodule Actuator do
  defrecord State, id: nil, monitor_pid: nil, f: nil, input_pids: nil

  def create(organism_pid) do
    spawn(Actuator, :start, [organism_pid])
  end

  def start(organism_pid) do
    IO.puts "Actuator begin #{inspect self}"

    receive do
      {^organism_pid, {id, monitor_pid, f, input_pids}} ->
        loop(State.new(id: id,
                       monitor_pid: monitor_pid,
                       f: f,
                       input_pids: input_pids),
             input_pids, [])
    end
  end

  def loop(s, [input_pid | input_pids], acc) do
    monitor_pid = s.monitor_pid

    receive do
      {^input_pid, :forward, input} ->
        loop(s, input_pids, :lists.append(input, acc))

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def loop(s, [], acc) do
    #Actuator.f(Enum.reverse(acc))
    case s.f do
      :pts -> pts(Enum.reverse(acc))
    end

    s.monitor_pid <- {self, :sync}
    loop(s, s.input_pids, [])
  end

  def pts(result) do
    :io.format("Actuator result: ~p~n", [result])
  end
end
