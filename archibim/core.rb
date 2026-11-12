# frozen_string_literal: true
# Pure Ruby calculations and validation. Intentionally independent of SketchUp.
require 'json'

module SSDigitalLab
  module ArchiBIM
    module Core
      EPS = 0.01
      ALLOWED_KINDS = %w[wall slab column beam stair room roof footing].freeze
      DEFAULTS = {
        'wall_height' => 3000.0, 'wall_thickness' => 150.0,
        'wall_exterior_side' => 'right',
        'auto_repair_scale' => true, 'auto_wall_join' => true,
        'wall_alignment' => 'center', 'column_alignment' => 'center', 'beam_alignment' => 'center',
        'slab_thickness' => 150.0, 'footing_thickness' => 450.0,
        'roof_thickness' => 125.0, 'roof_pitch' => 25.0, 'roof_overhang' => 450.0,
        'roof_type' => 'gable', 'roof_infill' => true, 'roof_infill_thickness' => 150.0,
        'roof_eave_offset' => 3000.0,
        'gutter_enabled' => false, 'downpipe_enabled' => false,
        'gutter_width' => 150.0, 'gutter_depth' => 100.0,
        'downpipe_diameter' => 75.0, 'downpipe_drop' => 3000.0,
        'truss_enabled' => false, 'truss_style' => 'king_post',
        'truss_spacing' => 1200.0, 'truss_member' => 75.0,
        'awning_posts' => true,
        'column_width' => 300.0,
        'column_depth' => 300.0, 'column_height' => 3000.0,
        'beam_width' => 300.0, 'beam_depth' => 450.0, 'beam_offset' => 2400.0,
        'door_width' => 900.0, 'door_height' => 2100.0,
        'door_mount' => 'center', 'window_mount' => 'center',
        'sliding_door_width' => 2400.0, 'sliding_door_height' => 2100.0,
        'sliding_door_mount' => 'center', 'sliding_door_panels' => 2,
        'sliding_door_direction' => 'left',
        'window_width' => 1200.0, 'window_height' => 1200.0, 'window_sill' => 900.0,
        'window_panels' => 2, 'window_outer_frame' => 50.0,
        'window_inner_frame' => 30.0, 'window_glass_thickness' => 3.0,
        'room_add_zone' => true, 'stair_cut_slab' => true, 'stair_hole_clearance' => 50.0,
        'stair_width' => 1100.0, 'stair_steps' => 18, 'stair_rise' => 3000.0,
        'stair_style' => 'straight', 'stair_landing' => 1100.0, 'stair_gap' => 150.0,
        'stair_structure' => 'waist', 'stair_waist' => 150.0,
        'stair_handrail' => 'both', 'stair_rail_height' => 950.0,
        'stair_rail_diameter' => 40.0, 'stair_post_spacing' => 900.0,
        'stair_max_riser' => 190.0, 'stair_min_tread' => 250.0,
        'rates' => { 'wall' => 120.0, 'slab' => 190.0, 'column' => 650.0,
                     'beam' => 650.0, 'stair' => 4000.0, 'room' => 0.0,
                     'door' => 450.0, 'window' => 650.0, 'sliding_door' => 1200.0,
                     'roof' => 165.0, 'footing' => 650.0 }
      }.freeze

      def self.number(value, name, min: 0.0, max: 1_000_000.0, allow_zero: false)
        n = Float(value)
        raise ArgumentError, "#{name} must be a finite number" unless n.finite?
        raise ArgumentError, "#{name} must be #{allow_zero ? 'at least' : 'greater than'} #{min}" if allow_zero ? (n < min) : (n <= min)
        raise ArgumentError, "#{name} must not exceed #{max}" if n > max
        n
      rescue TypeError, ArgumentError => e
        raise ArgumentError, e.message.include?(name) ? e.message : "Invalid #{name}"
      end

      # Keep UI dimension formatting strictly numeric. In v0.4 this accepted
      # Boolean family values, causing a NoMethodError in panel_payload every
      # time the user clicked a wall or attempted to change the active level.
      def self.numeric_dimensions(values)
        values.select { |v| v.is_a?(Numeric) && v.finite? }
      end

      def self.settings(raw)
        h = JSON.parse(JSON.generate(DEFAULTS))
        return h unless raw.is_a?(Hash)
        (DEFAULTS.keys - ['rates']).each do |key|
          next unless raw.key?(key)
          if %w[wall_alignment column_alignment beam_alignment].include?(key)
            raise ArgumentError, "#{key} must be left, center or right" unless %w[left center right].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'wall_exterior_side'
            raise ArgumentError, 'Exterior wall side must be left or right' unless %w[left right].include?(raw[key])
            h[key] = raw[key]
          elsif %w[door_mount window_mount sliding_door_mount].include?(key)
            raise ArgumentError, 'Frame mounting must be center, exterior or interior' unless %w[center exterior interior].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'sliding_door_direction'
            raise ArgumentError, 'Sliding direction must be left or right' unless %w[left right].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'roof_type'
            raise ArgumentError, 'Unknown roof style' unless %w[gable hip shed awning flat butterfly saltbox].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'truss_style'
            raise ArgumentError, 'Unknown truss pattern' unless %w[king_post fink].include?(raw[key])
            h[key] = raw[key]
          elsif %w[roof_infill auto_repair_scale stair_cut_slab room_add_zone gutter_enabled downpipe_enabled truss_enabled awning_posts].include?(key)
            h[key] = (raw[key] == true || raw[key].to_s == 'true' || raw[key] == 1)
          elsif key == 'stair_structure'
            raise ArgumentError, 'Stair construction must be waist or open' unless %w[waist open].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'stair_handrail'
            raise ArgumentError, 'Handrail must be none, left, right or both' unless %w[none left right both].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'stair_style'
            raise ArgumentError, 'Stair style must be straight or u' unless %w[straight u].include?(raw[key])
            h[key] = raw[key]
          elsif key == 'sliding_door_panels'
            h[key] = number(raw[key], key, min: 2, max: 4, allow_zero: true).to_i
          elsif key == 'window_panels'
            h[key] = number(raw[key], key, min: 0, max: 4).to_i
          elsif key == 'stair_steps'
            h[key] = number(raw[key], key, min: 0, max: 100).to_i
          elsif key == 'roof_pitch'
            h[key] = number(raw[key], key, min: 0, max: 79.9)
          elsif %w[beam_offset window_sill roof_overhang roof_eave_offset stair_hole_clearance].include?(key)
            h[key] = number(raw[key], key, min: 0, allow_zero: true)
          else
            h[key] = number(raw[key], key)
          end
        end
        if raw['rates'].is_a?(Hash)
          h['rates'].each_key do |key|
            next unless raw['rates'].key?(key)
            h['rates'][key] = number(raw['rates'][key], "rate #{key}", min: 0, allow_zero: true)
          end
        end
        h
      end

      def self.opening_valid?(opening, length, height, others = [])
        x = number(opening['offset'], 'opening offset', min: 0, allow_zero: true)
        w = number(opening['width'], 'opening width', min: 0)
        z = number(opening['sill'], 'opening sill', min: 0, allow_zero: true)
        h = number(opening['height'], 'opening height', min: 0)
        raise ArgumentError, 'Opening lies outside the wall length' if x + w > length + EPS
        raise ArgumentError, 'Opening extends beyond the wall top' if z + h > height + EPS
        others.each do |o|
          next if o['id'].to_s == opening['id'].to_s
          xx = Float(o['offset']); ww = Float(o['width'])
          zz = Float(o['sill']); hh = Float(o['height'])
          if [x, xx].max < [x + w, xx + ww].min - EPS &&
             [z, zz].max < [z + h, zz + hh].min - EPS
            raise ArgumentError, 'Openings cannot overlap'
          end
        end
        true
      end

      # Keep a dragged opening entirely on its host, even when the cursor is
      # beyond an endpoint. Openings still cannot overlap other openings.
      def self.clamp_opening_offset(center_mm, width_mm, wall_length_mm)
        width = number(width_mm, 'opening width')
        length = number(wall_length_mm, 'wall length')
        raise ArgumentError, 'Opening is wider than wall' if width > length + EPS
        [[Float(center_mm) - width / 2.0, 0.0].max, length - width].min
      end

      # 2D slab Boolean grid. Cells represent actual material, and cutouts are
      # clipped to slab bounds; overlap is a union rather than double subtraction.
      def self.slab_cells(width, depth, holes)
        w = number(width, 'slab width'); d = number(depth, 'slab depth')
        clipped = Array(holes).filter_map do |h|
          x0, x1 = [Float(h.fetch('x0')), Float(h.fetch('x1'))].minmax
          y0, y1 = [Float(h.fetch('y0')), Float(h.fetch('y1'))].minmax
          x0 = [[x0, 0.0].max, w].min; x1 = [[x1, 0.0].max, w].min
          y0 = [[y0, 0.0].max, d].min; y1 = [[y1, 0.0].max, d].min
          [x0,x1,y0,y1] if x1 - x0 > EPS && y1 - y0 > EPS
        end
        xs = ([0.0, w] + clipped.flat_map { |h| h[0,2] }).uniq.sort
        ys = ([0.0, d] + clipped.flat_map { |h| h[2,2] }).uniq.sort
        material = {}
        (0...(xs.size-1)).each do |i|
          (0...(ys.size-1)).each do |j|
            cx=(xs[i]+xs[i+1])/2.0; cy=(ys[j]+ys[j+1])/2.0
            next if clipped.any? { |h| cx > h[0]+EPS && cx < h[1]-EPS && cy > h[2]+EPS && cy < h[3]-EPS }
            material[[i,j]]=[xs[i],xs[i+1],ys[j],ys[j+1]]
          end
        end
        [xs,ys,material]
      end

      def self.slab_net_area_mm2(width, depth, holes)
        _xs, _ys, cells = slab_cells(width, depth, holes)
        cells.values.sum { |x0,x1,y0,y1| (x1-x0)*(y1-y0) }
      end

      def self.wall_cells(length, height, openings)
        length = number(length, 'wall length')
        height = number(height, 'wall height')
        openings.each_with_index do |opening, i|
          opening_valid?(opening, length, height, openings.each_with_index.reject { |_, j| j == i }.map(&:first))
        end
        xs = ([0.0, length] + openings.flat_map { |o| [o['offset'].to_f, o['offset'].to_f + o['width'].to_f] }).uniq.sort
        zs = ([0.0, height] + openings.flat_map { |o| [o['sill'].to_f, o['sill'].to_f + o['height'].to_f] }).uniq.sort
        cells = {}
        (0...(xs.length - 1)).each do |i|
          (0...(zs.length - 1)).each do |j|
            next if xs[i + 1] - xs[i] < EPS || zs[j + 1] - zs[j] < EPS
            cx = (xs[i] + xs[i + 1]) / 2.0
            cz = (zs[j] + zs[j + 1]) / 2.0
            cut = openings.any? { |o| cx > o['offset'].to_f + EPS && cx < o['offset'].to_f + o['width'].to_f - EPS &&
                                      cz > o['sill'].to_f + EPS && cz < o['sill'].to_f + o['height'].to_f - EPS }
            cells[[i, j]] = [xs[i], xs[i + 1], zs[j], zs[j + 1]] unless cut
          end
        end
        [xs, zs, cells]
      end

      def self.quantities(data)
        kind = data.fetch('kind')
        q = { 'count' => 1, 'length_m' => 0.0, 'area_m2' => 0.0,
              'volume_m3' => 0.0, 'net_area_m2' => 0.0, 'gross_area_m2' => 0.0 }
        case kind
        when 'wall'
          len = Float(data['length']); h = Float(data['height']); th = Float(data['thickness'])
          open = (data['openings'] || []).sum { |o| o['width'].to_f * o['height'].to_f }
          q['length_m'] = len / 1000.0
          q['gross_area_m2'] = len * h / 1_000_000.0
          q['net_area_m2'] = (len * h - open) / 1_000_000.0
          q['area_m2'] = q['net_area_m2']
          q['volume_m3'] = q['net_area_m2'] * th / 1000.0
        when 'slab'
          q['area_m2'] = Float(data['width']) * Float(data['depth']) / 1_000_000.0
          q['net_area_m2'] = slab_net_area_mm2(data['width'], data['depth'], data.fetch('cutouts', [])) / 1_000_000.0
          q['volume_m3'] = q['net_area_m2'] * Float(data['thickness']) / 1000.0

        when 'footing'
          q['area_m2'] = Float(data['width']) * Float(data['depth']) / 1_000_000.0
          q['volume_m3'] = q['area_m2'] * Float(data['thickness']) / 1000.0
        when 'roof'
          w = Float(data['width']) + 2.0 * Float(data['overhang'])
          d = Float(data['depth']) + 2.0 * Float(data['overhang'])
          pitch = Float(data['pitch']) * Math::PI / 180.0
          q['area_m2'] = (w / Math.cos(pitch)) * d / 1_000_000.0
          q['net_area_m2'] = q['area_m2']
          q['volume_m3'] = w * d * Float(data['thickness']) / 1_000_000_000.0
        when 'column'
          q['volume_m3'] = Float(data['width']) * Float(data['depth']) * Float(data['height']) / 1_000_000_000.0
        when 'beam'
          q['length_m'] = Float(data['length']) / 1000.0
          q['volume_m3'] = Float(data['length']) * Float(data['width']) * Float(data['depth']) / 1_000_000_000.0
        when 'stair'
          q['count'] = 1
          run = Float(data['run']); width = Float(data['width'])
          rise = Float(data['rise']); steps = Float(data['steps'])
          q['length_m'] = run / 1000.0
          if data.fetch('style', 'straight') == 'u'
            first = (steps / 2.0).ceil
            second = steps - first
            landing = Float(data.fetch('landing', width))
            gap = Float(data.fetch('gap', 150.0))
            tread = (run - landing) / first
            r = rise / steps
            flight1 = (first * (first + 1) / 2.0) * r * width * tread
            flight2 = (second * first + second * (second + 1) / 2.0) * r * width * tread
            landing_volume = (2 * width + gap) * landing * [first * r, 150.0].min
            q['volume_m3'] = (flight1 + flight2 + landing_volume) / 1_000_000_000.0
          else
            q['volume_m3'] = (run / steps) * width * (rise / steps) *
                             (steps * (steps + 1) / 2.0) / 1_000_000_000.0
          end
        when 'room'
          q['area_m2'] = Float(data['width']) * Float(data['depth']) / 1_000_000.0
          q['net_area_m2'] = q['area_m2']
        else
          raise ArgumentError, "Unsupported kind: #{kind}"
        end
        q
      end

      def self.cost(data, rates)
        q = quantities(data)
        r = Float(rates.fetch(data['kind'], 0.0))
        unit = case data['kind']
               when 'wall', 'slab' then q['net_area_m2']
               when 'room', 'roof' then q['area_m2']
               when 'column', 'beam', 'footing' then q['volume_m3']
               else 1
               end
        total = r * unit
        if data['kind'] == 'wall'
          (data['openings'] || []).each { |o| total += Float(rates.fetch(o['kind'], 0.0)) }
        end
        total
      end

      def self.default_levels
        [{ 'id' => 'GF', 'name' => 'Ground Floor', 'elevation' => 0.0 },
         { 'id' => 'L01', 'name' => 'First Floor', 'elevation' => 3000.0 }]
      end
    end
  end
end
