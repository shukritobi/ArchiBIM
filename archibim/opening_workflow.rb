# frozen_string_literal: true
# Explicit opening selection and atomic multi-wall editing.
module SSDigitalLab
  module ArchiBIM
    # The model's generated BIM groups live at root. Avoid scanning the dense
    # iPad Canvas/RoomPlan source hierarchy on each manager UI refresh.
    def self.opening_catalog
      Sketchup.active_model.entities.grep(Sketchup::Group).filter_map do |wall|
        data = data_for(wall)
        next unless data && data['kind'] == 'wall'
        Array(data['openings']).map do |opening|
          { 'id' => opening['id'], 'wall_id' => data['id'],
            'wall_name' => data.fetch('name', 'Wall'),
            'kind' => opening['kind'], 'width' => opening['width'],
            'height' => opening['height'], 'style' => opening.fetch('style','solid'),
            'operation' => opening.fetch('operation','casement') }
        end
      end.flatten
    end

    def self.opening_selection(id)
      Sketchup.active_model.entities.grep(Sketchup::Group).each do |wall|
        data = data_for(wall)
        next unless data && data['kind'] == 'wall'
        opening = Array(data['openings']).find { |o| o['id'] == id.to_s }
        return [wall, data, opening] if opening
      end
      raise ArgumentError, 'Opening ID not found in current BIM model'
    end

    def self.highlight_opening(id)
      wall, data, opening = opening_selection(id)
      @highlight_opening_id = id.to_s
      Sketchup.active_model.select_tool(OpeningFocusTool.new(wall, data, opening))
      refresh_panel
    end

    def self.highlight_opening_id
      @highlight_opening_id
    end

    # Validate all target walls before writing anything. If any width increase
    # overlaps or overruns another opening, fail the entire batch (one Undo).
    def self.batch_update_openings(ids, patch)
      ids = Array(ids).map(&:to_s).uniq
      raise ArgumentError, 'Choose at least one opening' if ids.empty?
      raise ArgumentError, 'Maximum 200 openings per batch' if ids.length > 200
      raise ArgumentError, 'Invalid bulk opening changes' unless patch.is_a?(Hash)
      allowed = %w[width height sill hinge swing style handle operation transom
                   transom_height outer_frame inner_frame glass_thickness panels]
      changes = patch.select { |key, value| allowed.include?(key) && !value.nil? && value.to_s != '' }
      raise ArgumentError, 'Choose at least one property to update' if changes.empty?
      by_wall = {}
      changed = []
      skipped = []
      ids.each do |id|
        group, original, target = opening_selection(id)
        entry = (by_wall[original['id']] ||= [group, JSON.parse(JSON.generate(original))])
        copy = entry[1]['openings'].find { |o| o['id'] == id }
        raise 'Internal opening mismatch' unless copy
        applied = []
        changes.each do |key, value|
          kind = copy['kind']
          next if %w[style handle].include?(key) && kind != 'door'
          next if key == 'operation' && kind != 'window'
          next if key == 'panels' && kind == 'door'
          next if key == 'swing' && kind == 'sliding_door'
          next if key == 'hinge' && kind == 'sliding_door'
          if %w[width height sill transom_height outer_frame inner_frame glass_thickness].include?(key)
            copy[key] = mm_from_user(value, key)
          elsif key == 'panels'
            copy[key] = Core.number(value, key, min: 1, max: 4, allow_zero: true).to_i
          elsif key == 'transom'
            copy[key] = (value == true || value.to_s == 'true')
          else
            copy[key] = value.to_s
          end
          applied << key
        end
        if applied.empty?
          skipped << id
        else
          Core.validate_opening_options!(copy)
          changed << id
        end
      end
      raise ArgumentError, 'No compatible changes for selected opening types' if changed.empty?
      by_wall.each_value { |_, data| validate_data(data) }
      model = Sketchup.active_model
      model.start_operation('ArchiBIM: Batch edit openings', true)
      begin
        by_wall.each_value do |group, data|
          group.transformation = Repair.normalized_transform(group.transformation)
          Geometry.build(group, data, model)
        end
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      Diagnostics.log('batch_openings_edit', { count: changed.size, skipped: skipped.size,
                                              affected_walls: by_wall.size, fields: changes.keys })
      refresh_panel
      { 'updated' => changed.size, 'skipped' => skipped.size,
        'walls' => by_wall.size }
    end

    class OpeningFocusTool
      def initialize(wall, data, opening)
        @wall, @data, @opening = wall, data, opening
      end

      def activate
        Sketchup.status_text = "ArchiBIM opening #{@opening['id'].to_s[0,8]} highlighted. Edit its matching inspector row; Esc exits highlight."
        Sketchup.active_model.active_view.invalidate
      end

      def onCancel(_reason, view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def draw(view)
        return unless @wall.valid?
        x0 = @opening['offset'].to_f
        x1 = x0 + @opening['width'].to_f
        z0 = @opening['sill'].to_f
        z1 = z0 + @opening['height'].to_f
        low, high = Junctions.side_offsets(@data['thickness'], @data['alignment'])
        view.line_width = 5
        view.line_stipple = ''
        view.drawing_color = Sketchup::Color.new(255, 192, 54)
        [low - 8.0, high + 8.0].each do |y|
          pts = [[x0,y,z0],[x1,y,z0],[x1,y,z1],[x0,y,z1]].map do |coords|
            Geometry.point(*coords).transform(@wall.transformation)
          end
          view.draw(GL_LINE_LOOP, pts)
        end
        label = "#{@opening['kind'].upcase} #{@opening['id'].to_s[0,8]} | #{@opening['width'].round} x #{@opening['height'].round} mm"
        anchor = Geometry.point((x0+x1)/2.0, high+20.0, z1+80).transform(@wall.transformation)
        view.draw_text(view.screen_coords(anchor), label, size: 15, bold: true)
      end

      def getExtents
        @wall.bounds
      end
    end
  end
end
