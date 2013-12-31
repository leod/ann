defmodule Morphology do
  def get_init_sensors([]) do
    [Genotype.Sensor.new(f: :rng, vl: 2),
     Genotype.Sensor.new(f: :rng, vl: 3)]
  end

  def get_init_actuators([]) do
    [Genotype.Actuator.new(f: :pts, vl: 3),
     Genotype.Actuator.new(f: :pts, vl: 1)]
  end
end
