defmodule Stats do
  import Enum

  def average(xs), do:
    :lists.sum(xs) / length(xs) 

  def standard_deviation(xs) do
    avg = average(xs) 

    n_variance = reduce xs, 0, fn x, acc ->
      :math.pow(avg - x, 2) + acc
    end 

    :math.sqrt(n_variance / length(xs))
  end
end
