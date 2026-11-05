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
        'slab_thickness' => 150.0, 'footing_thickness' => 450.0,
        'roof_thickness' => 125.0, 'roof_pitch' => 25.0, 'roof_overhang' => 450.0,
        'roof_eave_offset' => 3000.0, 'column_width' => 300.0,
        'column_depth' => 300.0, 'column_height' => 3000.0,
        'beam_width' => 300.0, 'beam_depth' => 450.0, 'beam_offset' => 2400.0,
        'door_width' => 900.0, 'door_height' => 2100.0,
        'window_width' => 1200.0, 'window_height' => 1200.0, 'window_sill' => 900.0,
        'stair_width' => 1100.0, 'stair_steps' => 18, 'stair_rise' => 3000.0,
        'rates' => { 'wall' => 120.0, 'slab' => 190.0, 'column' => 650.0,
                     'beam' => 650.0, 'stair' => 4000.0, 'room' => 0.0,
                     'door' => 450.0, 'window' => 650.0,
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

      def self.settings(raw)
        h = JSON.parse(JSON.generate(DEFAULTS))
        return h unless raw.is_a?(Hash)
        (DEFAULTS.keys - ['rates']).each do |key|
          next unless raw.key?(key)
          if key == 'stair_steps'
            h[key] = number(raw[key], key, min: 0, max: 100).to_i
          elsif key == 'roof_pitch'
            h[key] = number(raw[key], key, min: 0, max: 79.9)
          elsif %w[beam_offset window_sill roof_overhang roof_eave_offset].include?(key)
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
          q['net_area_m2'] = q['area_m2']
          q['volume_m3'] = q['area_m2'] * Float(data['thickness']) / 1000.0
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
          q['length_m'] = Float(data['run']) / 1000.0
          q['volume_m3'] = Float(data['run']) * Float(data['width']) * Float(data['rise']) * (Float(data['steps']) + 1) / (2.0 * Float(data['steps'])) / 1_000_000_000.0
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
               when 'wall', 'slab', 'room', 'roof' then q['area_m2']
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
