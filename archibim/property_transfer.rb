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

      def same_object?(a, b)
        a['id'].to_s == b['id'].to_s && !a['id'].nil?
      end
    end

    class PropertyEyedropperTool
      def initialize
        @source = nil
        @applied = 0
      end

      def activate
        Sketchup.status_text = 'ArchiBIM Eyedropper: click a source BIM element or hosted opening, then click matching targets. Esc exits.'
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
          Sketchup.status_text = 'Click a BIM element or an actual hosted frame/leaf.'
          return
        end
        unless @source
          @source = target
          Sketchup.status_text = "Source #{@source['kind']} captured. Click same-type targets. Width, length, sill, offset and host remain unchanged."
          return
        end
        if @source['kind'] != target['kind']
          Sketchup.status_text = "Cannot match #{@source['kind']} to #{target['kind']}; select a matching type."
          return
        end
        if PropertyTransfer.same_object?(@source['data'], target['data'])
          Sketchup.status_text = 'Source and target are the same object. Choose another target.'
          return
        end
        patch = PropertyTransfer.patch(@source['data'], target['data'])
        if patch.empty?
          Sketchup.status_text = 'Target already matches transferable source properties.'
          return
        end
        if target['host']
          ArchiBIM.patch_opening(target['data']['id'], patch, target['host'])
        else
          ArchiBIM.update_element(target['group'], patch)
        end
        @applied += 1
        Diagnostics.log('eyedropper_match', { 'kind' => target['kind'], 'target' => target['data']['id'], 'copied_fields' => patch.keys, 'count' => @applied })
        Sketchup.status_text = "Matched #{target['kind']} (#{@applied} target(s)); click another matching target, Esc exits."
        view.invalidate
      rescue StandardError => error
        Diagnostics.error('eyedropper_match', error)
        Sketchup.status_text = "Eyedropper skipped target: #{error.message}"
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate if view
      end
    end
  end
end
