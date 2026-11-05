# frozen_string_literal: true
# Dimension and construction calculations with no dependency on the SketchUp API.
module SSDigitalLab
  module ArchiBIM
    module StairMath
      module_function

      def flight_profile(risers:, going:, rise:, waist:, base: 0.0)
        n = Integer(risers)
        run = Float(going)
        total = Float(rise)
        structure = Float(waist)
        raise ArgumentError, 'At least two risers are required' if n < 2
        raise ArgumentError, 'Flight going and rise must be positive' unless run > 0 && total > 0
        raise ArgumentError, 'Waist thickness must be between 0 and flight rise' unless structure > 0 && structure < total
        # A flight with N risers has N-1 independent treads; the upper floor
        # acts as the final walking surface. This is the usual BIM convention.
        tread = run / (n - 1)
        riser = total / n
        points = [[0.0, base.to_f], [0.0, base.to_f + riser]]
        (1...n).each do |i|
          x = i * tread
          points << [x, base.to_f + i * riser]
          points << [x, base.to_f + (i + 1) * riser]
        end
        points << [run, base.to_f + total - structure]
        points
      end

      def layout(data)
        risers = Integer(data.fetch('steps'))
        rise = Float(data.fetch('rise'))
        going = Float(data.fetch('run'))
        width = Float(data.fetch('width'))
        raise ArgumentError, 'Stair needs at least two risers' if risers < 2
        if data.fetch('style', 'straight') == 'u'
          landing = Float(data.fetch('landing', width))
          gap = Float(data.fetch('gap', 150.0))
          count1 = (risers / 2.0).ceil
          count2 = risers - count1
          raise ArgumentError, 'U stair needs two risers in each run' if count2 < 2
          flight_going = going - landing
          raise ArgumentError, 'Landing must be shorter than stair run' if flight_going <= 0
          tread = flight_going / (count1 - 1)
          [{ 'risers' => count1, 'going' => flight_going,
             'rise' => rise * count1 / risers, 'base' => 0.0,
             'x' => 0.0, 'y' => 0.0, 'direction' => 1,
             'tread' => tread },
           { 'risers' => count2, 'going' => tread * (count2 - 1),
             'rise' => rise * count2 / risers,
             'base' => rise * count1 / risers,
             'x' => flight_going, 'y' => width + gap, 'direction' => -1,
             'tread' => tread }]
        else
          [{ 'risers' => risers, 'going' => going, 'rise' => rise,
             'base' => 0.0, 'x' => 0.0, 'y' => 0.0,
             'direction' => 1, 'tread' => going / (risers - 1) }]
        end
      end

      def warnings(data)
        runs = layout(data)
        step_height = Float(data['rise']) / Integer(data['steps'])
        tread = runs.first.fetch('tread')
        messages = []
        max_riser = Float(data.fetch('max_riser', 190.0))
        min_tread = Float(data.fetch('min_tread', 250.0))
        messages << "Riser #{step_height.round(1)} mm exceeds preferred #{max_riser.round} mm" if step_height > max_riser
        messages << "Going #{tread.round(1)} mm is below preferred #{min_tread.round} mm" if tread < min_tread
        messages
      end
    end
  end
end
