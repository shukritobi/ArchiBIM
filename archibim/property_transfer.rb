# frozen_string_literal: true
# Conservative Archicad-style eyedropper/syringe property matching.
# Source type must match target type; geometric identity is never copied.
module SSDigitalLab
  module ArchiBIM
    module PropertyTransfer
      extend self

      OPENING_FIELDS = {
        'window' => %w[height operation hinge marker mount transom transom_height outer_frame inner_frame glass_thickness],
        'door' => %w[height style handle hinge swing marker mount transom transom_height outer_frame glass_thickness leafless],
        'sliding_door' => %w[height slide_direction mount outer_frame inner_frame glass_thickness]
      }.freeze
      ELEMENT_FIELDS = {
        'wall' => %w[height exterior_side],
        'slab' => %w[thickness],
        'roof' => %w[thickness pitch roof_type overhang eave_offset infill infill_thickness gutter_enabled downpipe_enabled gutter_width gutter_depth downpipe_diameter downpipe_drop truss_enabled truss_style truss_spacing truss_member awning_posts],
        'column' => %w[height],
        'beam' => %w[depth offset],
        'stair' => %w[rise steps style landing gap structure waist handrail rail_height rail_diameter post_spacing max_riser min_tread cut_slab hole_clearance],
        'room' => [],
        'footing' => %w[thickness]
      }.freeze
      GLASS_WALL_FIELDS = %w[glass_wall_frame glass_wall_frame_width glass_wall_glass_thickness glass_wall_mullions_count glass_wall_mullion_width glass_wall_auto_transom glass_wall_corner_at glass_wall_corner_skin glass_wall_partition_above glass_wall_partition_height glass_wall_partition_thickness].freeze

      def patch(source, target)
        type = source.fetch('kind')
        raise ArgumentError, 'Eyedropper requires the same BIM element type' unless type == target['kind']
        allowed = OPENING_FIELDS[type] || ELEMENT_FIELDS[type]
        raise ArgumentError, 'Unsupported ArchiBIM element type' unless allowed
        allowed += GLASS_WALL_FIELDS if type == 'wall' &&
          source.fetch('wall_type','brick') == 'glass' &&
          target.fetch('wall_type','brick') == 'glass'
        allowed.each_with_object({}) do |key, output|
          output[key] = source[key] if source.key?(key) && source[key] != target[key]
        end
      end

      # Fit transferred opening settings within the *existing target* geometry.
      # A copied height must never move the sill or change a wall. If a taller
      # source collides with the head or an opening directly above, use the
      # largest safe target height and explain the adjustment to the user.
      def plan_for_host(source, target, wall)
        changes = patch(source, target)
        return [changes, []] unless OPENING_FIELDS.key?(target['kind'])
        notes = []
        if changes.key?('height')
          ceiling = wall.fetch('height').to_f
          left = target.fetch('offset').to_f
          right = left + target.fetch('width').to_f
          sill = target.fetch('sill', 0.0).to_f
          wall.fetch('openings', []).each do |other|
            next if same_object?(other, target)
            oleft = other.fetch('offset').to_f
            oright = oleft + other.fetch('width').to_f
            next unless [left, oleft].max < [right, oright].min - 0.01
            other_sill = other.fetch('sill', 0.0).to_f
            ceiling = [ceiling, other_sill].min if other_sill >= sill
          end
          room = ceiling - sill
          if room <= 0
            # Never delete or silently resize a previously valid target.
            changes.delete('height')
            notes << 'Source height not copied: no vertical clearance above existing sill'
          elsif changes['height'].to_f > room
            proposed = changes['height'].to_f
            changes['height'] = room
            notes << "Height fitted from #{proposed.round} to #{room.round} mm to preserve sill and wall"
          end
        end
        effective = target.merge(changes)
        if effective['transom'] == true &&
           effective.fetch('transom_height', 450.0).to_f + 170.0 >= effective['height'].to_f
          max_transom = (effective['height'].to_f - 171.0).floor
          if max_transom >= 50
            changes['transom_height'] = max_transom.to_f
            notes << "Upper fixed glass height fitted to #{max_transom} mm"
          else
            changes['transom'] = false
            changes.delete('transom_height')
            notes << 'Upper fixed glass disabled: insufficient target opening height'
          end
        end
        [changes, notes]
      end

      def same_object?(a, b)
        a['id'].to_s == b['id'].to_s && !a['id'].nil?
      end
    end

    class PropertyEyedropperTool
      def initialize
        @source = nil
        @applied = 0
      end

      def feedback(message)
        Sketchup.status_text = "ArchiBIM Eyedropper: #{message}"
        dialog = ArchiBIM.instance_variable_get(:@dialog)
        return unless dialog && dialog.visible?
        dialog.execute_script("window.ArchiBIM?.eyedropperStatus(#{JSON.generate(message)})")
      rescue StandardError => error
        Diagnostics.error('eyedropper_feedback', error)
      end

      def activate
        feedback('Click a SOURCE window, door or wall in the model, then click its matching TARGET.')
      end

      def deactivate(view)
        view.invalidate if view
      end

      def pick(view, x, y)
        picker = view.pick_helper
        picker.do_pick(x, y)
        (0...picker.count).each do |i|
          path = picker.path_at(i)
          next unless path
          host = path.find do |entity|
            entity.is_a?(Sketchup::Group) && ArchiBIM.data_for(entity)&.fetch('kind', nil) == 'wall'
          end
          opening_group = path.find do |entity|
            entity.is_a?(Sketchup::Group) && entity.valid? &&
              entity.get_attribute(ArchiBIM::DICT, 'hosted') == true
          end
          if host && opening_group
            detail = ArchiBIM.safe_json(opening_group.get_attribute(ArchiBIM::DICT, 'data'), nil)
            if detail && %w[door window sliding_door].include?(detail['kind'])
              opening = ArchiBIM.data_for(host).fetch('openings', []).find { |o| o['id'] == detail['id'] }
              return { 'kind' => detail['kind'], 'data' => opening, 'host' => host } if opening
            end
          end
          group = path.find { |e| e.is_a?(Sketchup::Group) && ArchiBIM.data_for(e) }
          data = ArchiBIM.data_for(group) if group
          return { 'kind' => data['kind'], 'data' => data, 'group' => group } if data
        end
        nil
      end

      def onMouseMove(_flags, x, y, view)
        item = pick(view, x, y)
        view.tooltip = if item
          @source ? "Apply #{@source['kind']} settings to #{item['kind']} (preserve width and position)" :
                    "Pick source #{item['kind']}"
        else
          'Hover an ArchiBIM BIM object'
        end
      end

      def onLButtonDown(_flags, x, y, view)
        target = pick(view, x, y)
        unless target
          feedback('Click a BIM element or an actual hosted window frame or glass.')
          return
        end
        unless @source
          @source = target
          feedback("Source #{@source['kind']} captured. Click matching targets. Width, sill, offset and host stay unchanged.")
          return
        end
        if @source['kind'] != target['kind']
          feedback("Incompatible: #{@source['kind']} to #{target['kind']}. Select a matching target or press R to repick source.")
          return
        end
        if PropertyTransfer.same_object?(@source['data'], target['data'])
          feedback('Source and target are the same object. Choose another target.')
          return
        end
        patch, notes = if target['host']
                         PropertyTransfer.plan_for_host(@source['data'], target['data'],
                           ArchiBIM.data_for(target['host']))
                       else
                         [PropertyTransfer.patch(@source['data'], target['data']), []]
                       end
        if patch.empty?
          feedback('Target already matches transferable settings, or geometry prevents copying.')
          return
        end
        if target['host']
          ArchiBIM.patch_opening(target['data']['id'], patch, target['host'])
        else
          ArchiBIM.update_element(target['group'], patch)
        end
        @applied += 1
        Diagnostics.log('eyedropper_match', { 'kind' => target['kind'],
          'target' => target['data']['id'], 'copied_fields' => patch.keys,
          'adjustments' => notes, 'count' => @applied })
        message = "Matched #{target['kind']} (#{@applied} target(s))."
        message += " #{notes.join('; ')}." unless notes.empty?
        feedback("#{message} Click another target, R to repick source, Esc exits.")
        view.invalidate
      rescue StandardError => error
        Diagnostics.error('eyedropper_match', error)
        Diagnostics.log('eyedropper_skipped', { 'reason' => error.message,
          'source' => @source && @source['data']['id'],
          'target' => target && target['data'] && target['data']['id'] })
        feedback("Target unchanged: #{error.message}. R repicks source; click another target or Esc exits.")
      end

      def onKeyDown(key, _repeat, _flags, view)
        return unless key == 82 || key == 114 # R: choose new source
        @source = nil
        feedback('Source cleared. Click a new source object.')
        view.invalidate
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate if view
      end
    end
  end
end
