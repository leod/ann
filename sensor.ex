defmodule Sensor do
  import Enum

  def create(mapper_pid) do
    spawn(Sensor, :loop, [mapper_pid])
  end

  def loop(mapper_pid) do
    IO.puts "Sensor begin #{inspect self}"

    receive do
      {^mapper_pid, {id, monitor_pid, f, vl, output_pids}} ->
        loop(id, monitor_pid, f, vl, output_pids)
    end
  end

  def loop(id, monitor_pid, f, vl, output_pids) do
    receive do
      {^monitor_pid, :sync} ->
        #v = f.(vl)
        v = case f do
          :rng -> rng(vl)
        end
        map output_pids, fn pid ->
          pid <- {self, :forward, v}
        end

        loop(id, monitor_pid, f, vl, output_pids)

      {^monitor_pid, :terminate} ->
        :ok
    end
  end

  def rng(vl) do
    map(:lists.seq(1, vl), fn _ -> :random.uniform() end)
  end
end
