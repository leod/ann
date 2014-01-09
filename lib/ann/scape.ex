defmodule Scape do
  import Enum

  def create(organism_pid) do
    spawn(Scape, :start, [organism_pid])
  end

  def start(organism_pid) do
    receive do
      {^organism_pid, :xor_sim, _} ->
        xor_sim(organism_pid)
      {^organism_pid, :img_sim, :train} ->
        :wx.new()
        image = :wxImage.new()
        :wxImage.loadFile(image, 'test.png')
        data = :wxImage.getData(image) |> :binary.bin_to_list
        {0, gray_data} = reduce data, {0, []}, fn
          d, {0, gs} -> {1, [d * 2 / 255 - 1 | gs]}
          _, {1, gs} -> {2, gs}
          _, {2, gs} -> {0, gs}
        end
        width = :wxImage.getWidth(image)
        height = :wxImage.getHeight(image)
        :wx.destroy()

        true = (length(gray_data) == width*height)
        {coords, _} = map_reduce gray_data, {0, 0}, fn
          _, {^width, y} -> {{0, y+1}, {1, y+1}}
          _, {x, y} -> {{x, y}, {x+1, y}}
        end

        img_list = zip(coords, gray_data) |> map(fn {{x, y}, d} ->
          input = [x * 2 / (width-1) - 1, y * 2 / (height-1) - 1]
          correct_output = [d]
          {input, correct_output}
        end)

        #IO.inspect img_list

        img_sim(organism_pid, img_list, img_list, [])
      {^organism_pid, :img_sim, :trace} ->
        :wx.new()
        image = :wxImage.new()
        :wxImage.loadFile(image, 'test.png')
        width = :wxImage.getWidth(image)
        height = :wxImage.getHeight(image)
        :wx.destroy()

        img_sim_trace_init(organism_pid, width, height, 1)
      {^organism_pid, :img_sim, :trace_extrapolate} ->
        :wx.new()
        image = :wxImage.new()
        :wxImage.loadFile(image, 'test.png')
        width = :wxImage.getWidth(image)
        height = :wxImage.getHeight(image)
        :wx.destroy()

        img_sim_trace_init(organism_pid, width, height, 24)
    end
  end

  def img_sim_trace_init(organism_pid, width, height, scale) do
    s_width = scale*width
    s_height = scale*height

    {inputs, _} = map_reduce 1..s_width*s_height, {0, 0}, fn
      _, {^s_width, y} -> {{0, y+1}, {1, y+1}}
      _, {x, y} -> {{x, y}, {x+1, y}}
    end

    scaled_inputs = map inputs, fn {x, y} ->
      [x * 2 / (s_width-1) - 1, y * 2 / (s_height-1) - 1]
    end

    #IO.inspect scaled_inputs

    frame = {width, height, scale}
    img_sim_trace(organism_pid, scaled_inputs, frame, [])
  end

  def img_sim_trace(organism_pid, [input | inputs], frame, acc_output) do
    receive do
      {from, :sense} ->
        from <- {self, :input, input}
        img_sim_trace(organism_pid, [input | inputs], frame, acc_output)

      {from, :act, output} ->
        if inputs != [] do
          from <- {self, 0, 0}
          img_sim_trace(organism_pid, inputs, frame, acc_output ++ output)
        else
          # Save image for debugging
          data = map(acc_output ++ [output], fn x ->
                   s = cond do
                     x > 1 -> 1
                     x < -1 -> -1
                     true -> x
                   end
                   d = round(s * 255 / 2 + 255 / 2)
                   [d, d, d]
                 end)
                 |> concat
                 |> :binary.list_to_bin

          {width, height, scale} = frame

          # FITNESS CHECK
          :wx.new()
          if scale == 1 do
            x = fn ->
              image = :wxImage.new()
              :wxImage.loadFile(image, 'test.png')
              data = :wxImage.getData(image) |> :binary.bin_to_list
              {0, gray_data} = reduce data, {0, []}, fn
                d, {0, gs} -> {1, [d * 2 / 255 - 1 | gs]}
                _, {1, gs} -> {2, gs}
                _, {2, gs} -> {0, gs}
              end
              width = :wxImage.getWidth(image)
              height = :wxImage.getHeight(image)

              true = (length(gray_data) == width*height)
              {coords, _} = map_reduce gray_data, {0, 0}, fn
                _, {^width, y} -> {{0, y+1}, {1, y+1}}
                _, {x, y} -> {{x, y}, {x+1, y}}
              end

              img_list = zip(coords, gray_data) |> map(fn {{x, y}, d} ->
                input = [x * 2 / (width-1) - 1, y * 2 / (height-1) - 1]
                correct_output = [d]
                {input, correct_output}
              end)

              correct_outputs = map(img_list, fn {_i, o} -> o end) |> concat

              error = list_compare(correct_outputs, acc_output ++ output)
              fitness = 1 / (error + 0.00001)

              IO.puts "FITNESS CHECK #{fitness}"
            end
            x.()
          end

          image = :wxImage.new(width*scale, height*scale, data)
          :wxImage.saveFile(image, 'img_out_scale_#{scale}.png')
          :wx.destroy()

          from <- {self, 0, 1}
          receive do
            {^organism_pid, :terminate} ->
              organism_pid <- {self,:finished}
          end
        end

      {organism_pid, :terminate} ->
        organism_pid <- {self, :finished}
    end 
  end

  def img_sim(organism_pid, [{input, correct_output} | img_list], all_img_list,
              acc_output) do
    receive do
      # Input requested from sensor
      {from, :sense} ->
        #IO.puts "SCAPE SENSE #{inspect input}"
        from <- {self(), :input, input}
        img_sim(organism_pid, [{input, correct_output} | img_list],
                all_img_list, acc_output)

      # Output given from actuator, compare to correct output
      {from, :act, output} ->
        if img_list != [] do
          from <- {self, 0, 0}
          img_sim(organism_pid, img_list, all_img_list, acc_output ++ output)
        else
          correct_outputs = map(all_img_list, fn {_i, o} -> o end) |> concat

          error = list_compare(correct_outputs, acc_output ++ output)
          fitness = 1 / (error + 0.00001)
          from <- {self, fitness, 1}

          img_sim(organism_pid, all_img_list, all_img_list, [])
        end

      {^organism_pid, :terminate} ->
        organism_pid <- {self, :finished}
    end
  end

  defp list_compare(a, b)
  when length(a) == length(b) do
    zip(a, b)
    |> reduce(0, fn {x, y}, e -> e + :math.pow(x - y, 2) end)
    #|> :math.sqrt()
  end

  def xor_sim(organism_pid) do
    # Expected values for XOR
    xor_list = [{[-1, -1], [-1]},
                {[1, -1], [1]},
                {[-1, 1], [1]},
                {[1, 1], [-1]}]

    xor_sim(organism_pid, xor_list, xor_list, 0)
  end

  def xor_sim(organism_pid, [{input, correct_output} | xor_list], all_xor_list, acc_err) do
    receive do
      # Input requested from sensor
      {from, :sense} ->
        #IO.puts "SCAPE SENSE #{inspect input}"
        from <- {self(), :input, input}
        xor_sim(organism_pid, [{input, correct_output} | xor_list], all_xor_list, acc_err)

      # Output given from actuator, compare to correct output
      {from, :act, output} ->
        #IO.puts "SCAPE ACT #{inspect output}"
        err = list_compare(output, correct_output)

        case xor_list do
          [] ->
            fitness = 1 / (acc_err + err + 0.00001)
            from <- {self, fitness, 1}
            xor_sim(organism_pid, all_xor_list, all_xor_list, 0)

          _ ->
            from <- {self, 0, 0}
            xor_sim(organism_pid, xor_list, all_xor_list, acc_err + err)
        end

      {^organism_pid, :terminate} ->
        organism_pid <- {self, :finished}
    end
  end
end
