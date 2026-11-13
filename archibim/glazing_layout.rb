# frozen_string_literal: true
# Pure mm-space algorithms for glazed walls. Does not depend on SketchUp.
module SSDigitalLab
  module ArchiBIM
    module GlazingLayout
      extend self
      EPS = 0.001

      def segments_outside_openings(length, openings, z0, z1)
        spans = [[0.0, length.to_f]]
        Array(openings).each do |o|
          bottom, top = o.fetch('sill', 0.0).to_f, o.fetch('sill', 0.0).to_f + o.fetch('height', 0.0).to_f
          next unless top > z0 + EPS && bottom < z1 - EPS
          left, right = o['offset'].to_f, o['offset'].to_f + o['width'].to_f
          spans = spans.flat_map do |a,b|
            [[a,[b,left].min],[[a,right].max,b]].select { |m,n| n-m > EPS }
          end
        end
        spans
      end

      def vertical_stations(length, mullions)
        count = Integer(mullions)
        raise ArgumentError, 'Mullions must be 0 to 30' unless count.between?(0,30)
        (1..count).map { |index| length.to_f * index / (count+1.0) }
      end

      def active_vertical_stations(length, openings, count)
        vertical_stations(length,count).reject do |x|
          Array(openings).any? { |o| x > o['offset'].to_f-EPS && x < o['offset'].to_f + o['width'].to_f+EPS && o.fetch('sill',0).to_f < 100.0 }
        end
      end

      def transom_stations(wall)
        return [] unless wall.fetch('glass_wall_auto_transom',true)
        h = wall.fetch('height').to_f
        Array(wall.fetch('openings',[])).filter_map do |o|
          next unless %w[door sliding_door].include?(o['kind'])
          top = o.fetch('sill',0.0).to_f + o.fetch('height',0.0).to_f
          top if top + 80.0 < h
        end.uniq.sort
      end

      def pane_rectangles(wall)
        length = Float(wall.fetch('length'))
        height = Float(wall.fetch('height'))
        framed = wall.fetch('glass_wall_frame',true)
        border = framed ? Float(wall.fetch('glass_wall_frame_width',30.0)) : 0.0
        mullion = Float(wall.fetch('glass_wall_mullion_width',20.0))
        openings = Array(wall.fetch('openings',[]))
        stations = active_vertical_stations(length,openings,wall.fetch('glass_wall_mullions_count',0))
        transoms = transom_stations(wall)
        # Full rectilinear partition of the wall. Skip any part occupied by a host opening.
        xs = ([0.0,length] + openings.flat_map { |o| [o['offset'].to_f,o['offset'].to_f+o['width'].to_f] } + stations).uniq.sort
        zs = ([0.0,height] + openings.flat_map { |o| [o.fetch('sill',0.0).to_f,o.fetch('sill',0.0).to_f+o['height'].to_f] } + transoms).uniq.sort
        cut = -> (p,cuts) { cuts.any? { |n| (p-n).abs < EPS } }
        panes=[]
        xs.each_cons(2) do |xa,xb|
          zs.each_cons(2) do |za,zb|
            mid_x=(xa+xb)/2.0
            mid_z=(za+zb)/2.0
            next if openings.any? { |o| mid_x > o['offset'].to_f-EPS && mid_x < o['offset'].to_f+o['width'].to_f+EPS &&
              mid_z > o.fetch('sill',0.0).to_f-EPS && mid_z < o.fetch('sill',0.0).to_f+o['height'].to_f+EPS }
            x0 = xa + (xa.zero? && framed ? border+3.0 : 0.0)
            x1 = xb - ((xb-length).abs < EPS && framed ? border+3.0 : 0.0)
            z0 = za + (za.zero? && framed ? border+3.0 : 0.0)
            z1 = zb - ((zb-height).abs < EPS && framed ? border+3.0 : 0.0)
            x0 += mullion/2.0+3.0 if cut.call(xa,stations)
            x1 -= mullion/2.0+3.0 if cut.call(xb,stations)
            z0 += border+3.0 if cut.call(za,transoms)
            z1 -= 3.0 if cut.call(zb,transoms)
            # Small clearance at open jamb/sill/head boundaries.
            openings.each do |o|
              left,right=o['offset'].to_f,o['offset'].to_f+o['width'].to_f
              bottom,top=o.fetch('sill',0.0).to_f,o.fetch('sill',0.0).to_f+o['height'].to_f
              x0 += 3.0 if (xa-right).abs < EPS && mid_z.between?(bottom-EPS,top+EPS)
              x1 -= 3.0 if (xb-left).abs < EPS && mid_z.between?(bottom-EPS,top+EPS)
              z0 += 3.0 if (za-top).abs < EPS && mid_x.between?(left-EPS,right+EPS)
              z1 -= 3.0 if (zb-bottom).abs < EPS && mid_x.between?(left-EPS,right+EPS)
            end
            panes << [x0,x1,z0,z1] if x1-x0 > 5 && z1-z0 > 5
          end
        end
        panes
      end

      def mitered_frame?(wall, end_name)
        wall.fetch('glass_wall_corner_at','none').to_s.split(',').include?(end_name) ||
          wall.fetch('glass_wall_corner_at','none') == 'both'
      end

      def transom_width(wall)
        [wall.fetch('glass_wall_mullion_width',20.0).to_f, wall.fetch('glass_wall_frame_width',30.0).to_f].min
      end
    end
  end
end
