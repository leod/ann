defmodule Morphology do
  def get_init_sensors([]) do
    [Genotype.Sensor.new(f: :xor_get_input,
                         vl: 2,
                         scape: {:private, :xor_sim})]
  end

  def get_init_actuators([]) do
    [Genotype.Actuator.new(f: :xor_send_output,
                           vl: 1,
                           scape: {:private, :xor_sim})]
  end

  def get_sensors([]) do
    []
  end

  def get_actuators([]) do
    []
  end
end
