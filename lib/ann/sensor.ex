defmodule Sensor do
  import Enum

  defrecord State, id: nil, monitor_pid: nil, f: nil, scape: nil, vl: nil, output_pids: nil

  def create(organism_pid) do
    spawn(Sensor, :start, [organism_pid])
  end

  def start(organism_pid) do
    #IO.puts "Sensor begin #{inspect self}"

    receive do
      {^organism_pid, {id, monitor_pid, f, scape, vl, output_pids}} ->
        loop(State.new(id: id,
                       monitor_pid: monitor_pid,
                       f: f,
                       scape: scape,
                       vl: vl,
                       output_pids: output_pids))
    end
  end

  def loop(s) do
    monitor_pid = s.monitor_pid

    receive do
      {^monitor_pid, :sync} ->
        v = apply(Sensor, s.f, [s.vl, s.scape])

        map s.output_pids, fn pid ->
          pid <- {self, :forward, v}
        end

        loop(s)

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def rng(vl) do
    map(:lists.seq(1, vl), fn _ -> :random.uniform() end)
  end

  def xor_get_input(vl, scape) do
    scape <- {self, :sense}

    receive do
      {scape, :input, v} ->
        v
    end
  end
end
