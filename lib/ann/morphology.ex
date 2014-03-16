defmodule Morphology do
  def get_init_sensors([]) do
    [Genotype.Sensor.new(f: :xor_get_input,
                         vl: 2,
                         scape: {:private, :xor_sim})]
  end

  def get_init_sensors(:img_mimic) do
    [Genotype.Sensor.new(f: :img_get_input,
                         vl: 2,
                         scape: {:private, :img_sim})]
  end

  def get_init_sensors(:game_2048) do
    [Genotype.Sensor.new(f: :game_2048_get_input,
                         vl: 16,
                         scape: {:private, :game_2048_sim})]
  end

  def get_init_actuators([]) do
    [Genotype.Actuator.new(f: :xor_send_output,
                           vl: 2,
                           scape: {:private, :xor_sim})]
  end

  def get_init_actuators(:img_mimic) do
    # hack
    #:wx.new()
    #image = :wxImage.new()
    #:wxImage.loadFile(image, 'test2.png')
    #vl = :wxImage.getData(image) |> :binary.bin_to_list |> length |> div(3)
    #:wx.destroy()

    [Genotype.Actuator.new(f: :img_send_output,
                           vl: 1,
                           scape: {:private, :img_sim})]
  end

  def get_init_actuators(:game_2048) do
    [Genotype.Actuator.new(f: :game_2048_send_output,
                           vl: 1,
                           scape: {:private, :game_2048_sim})] 
  end

  def get_sensors([]) do
    []
  end

  def get_sensors(:img_mimic) do
    []
  end

  def get_actuators([]) do
    []
  end

  def get_actuators(:img_mimic) do
    []
  end
end
