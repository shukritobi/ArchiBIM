# frozen_string_literal: true
# One-click nested opening picking and two-endpoint hosted opening placement.
module SSDigitalLab
  module ArchiBIM
    class OpeningPathTool < OpeningTool
      def initialize(kind)
        super(kind)
        @start_x=nil
        @start_wall=nil
        @input=Sketchup::InputPoint.new
        @anchor=nil
      end

      def activate
        Sketchup.status_text = "ArchiBIM #{@kind}: click first wall point, then second point on same wall. SketchUp endpoint/edge inference enabled; Esc cancels."
      end

      def onMouseMove(_flags,x,y,view)
        candidate=@start_wall || find_host(view,x,y)
        @wall=candidate
        @hit=nil
        @valid=false
        if candidate
          @input.pick(view,x,y,@anchor) if @anchor
          @input.pick(view,x,y) unless @anchor
          @hit=cursor_position(view,x,y,candidate)
          if @input.valid?
            local=@input.position.transform(candidate.transformation.inverse)
            dx=(local.x.to_mm-@hit).abs
            # Only accept a native inference point sufficiently near the host
            # local wall axis and projected ray to avoid snapping to other floors.
            @hit=local.x.to_mm if dx<40.0
          end
          if @start_x
            d=ArchiBIM.data_for(candidate)
            offset=[@start_x,@hit].min
            width=(@hit-@start_x).abs
            height=ArchiBIM.settings["#{@kind}_height"]
            sill=@kind=='window' ? ArchiBIM.settings['window_sill'] : 0.0
            if width>=100.0
              begin
                Core.opening_valid?({'kind'=>@kind,'offset'=>offset,'width'=>width,
                  'height'=>height,'sill'=>sill},d['length'],d['height'],d['openings']||[])
                @valid=true
              rescue StandardError
                @valid=false
              end
            end
          else
            @valid=true
          end
          view.tooltip=@start_x ? "Width #{ArchiBIM.fmt_mm((@hit-@start_x).abs)}; click to complete" : @input.tooltip
        end
        view.invalidate
      rescue StandardError
        @valid=false
      end

      def onLButtonDown(flags,x,y,view)
        onMouseMove(flags,x,y,view)
        unless @wall && @hit && @valid
          Sketchup.status_text='Choose an ArchiBIM wall point without overlap; minimum width 100mm.'
          return
        end
        if @start_x.nil?
          @start_x=@hit
          @start_wall=@wall
          @anchor=Sketchup::InputPoint.new(@input.valid? ? @input.position :
            Geometry.point(@hit,0,0).transform(@wall.transformation))
          Sketchup.status_text='First endpoint fixed. Click second point on same wall or type width in Measurements.'
          return
        end
        width=(@hit-@start_x).abs
        offset=[@hit,@start_x].min
        ArchiBIM.place_opening(@wall,@kind,offset+width/2.0,
          {'width'=>width,'offset'=>offset,'hinge'=>@kind=='window' ? ArchiBIM.settings.fetch('window_hinge','left') : @hinge,
           'swing'=>@swing})
        @start_x=nil;@start_wall=nil;@anchor=nil
        Sketchup.status_text='Opening created. Click first point to begin another.'
        view.invalidate
      rescue StandardError => error
        UI.messagebox("ArchiBIM opening path: #{error.message}")
      end

      def onCancel(_reason,view)
        @start_x=nil;@start_wall=nil;@anchor=nil
        view.invalidate
      end

      def onUserText(text,view)
        return unless @start_x && @start_wall
        width=ArchiBIM.mm_from_user(text,'opening path width')
        raise ArgumentError,'Opening must be wider than 100mm' if width<100.0
        wall=ArchiBIM.data_for(@start_wall)
        raise 'Width crosses wall end' if @start_x+width>wall['length'].to_f+0.01
        ArchiBIM.place_opening(@start_wall,@kind,@start_x+width/2.0,
          {'width'=>width,'offset'=>@start_x,
           'hinge'=>@kind=='window' ? ArchiBIM.settings.fetch('window_hinge','left') : @hinge})
        @start_x=nil;@start_wall=nil;@anchor=nil
        view.invalidate
      rescue StandardError => error
        UI.messagebox("ArchiBIM path width: #{error.message}")
      end

      def draw(view)
        return unless @wall && @hit
        d=ArchiBIM.data_for(@wall)
        return unless d
        low,high=Junctions.side_offsets(d['thickness'],d['alignment'])
        z=d['height'].to_f+50.0
        view.line_width=3
        view.drawing_color=@valid ? Sketchup::Color.new(34,200,146) : Sketchup::Color.new(238,88,72)
        if @start_x
          p0=Geometry.point(@start_x,(low+high)/2.0,z).transform(@wall.transformation)
          p1=Geometry.point(@hit,(low+high)/2.0,z).transform(@wall.transformation)
          view.draw(GL_LINES,[p0,p1])
          if @valid
            face=[[[@start_x,@hit].min,low,z],[[@start_x,@hit].max,low,z],
                  [[@start_x,@hit].max,high,z],[[@start_x,@hit].min,high,z]]
            view.draw(GL_LINE_LOOP,face.map { |c| Geometry.point(*c).transform(@wall.transformation) })
          end
        end
        @input.draw(view) if @input && @input.valid? && @input.display?
      end
    end

    class OpeningSelectionTool
      def initialize
        @ids=[]
        @hover_id=nil
      end

      def activate
        Sketchup.status_text='ArchiBIM: click door/window surface to edit. Shift-click selects multiple; right click also selects. Esc closes.'
      end

      def find_opening(view,x,y)
        helper=view.pick_helper
        helper.do_pick(x,y)
        (0...helper.count).each do |i|
          path=helper.path_at(i)
          next unless path
          # Prefer the explicit hosted opening parent, not nested handle parts.
          found=path.find do |entity|
            entity.is_a?(Sketchup::Group) &&
              entity.get_attribute('SSDigitalLab_ArchiBIM','hosted',false)
          end
          next unless found
          raw=found.get_attribute('SSDigitalLab_ArchiBIM','data')
          begin
            id=JSON.parse(raw)['id']
            return id if id
          rescue JSON::ParserError,TypeError
          end
        end
        nil
      end

      def onMouseMove(_flags,x,y,view)
        @hover_id=find_opening(view,x,y)
        view.tooltip=@hover_id ? "Door/window #{@hover_id[0,8]} · click to edit" : 'Click a door/window'
        view.invalidate
      end

      def onLButtonDown(flags,x,y,view)
        id=find_opening(view,x,y)
        return unless id
        shift=(flags & CONSTRAIN_MODIFIER_MASK) != 0 rescue false
        @ids=[] unless shift
        if shift && @ids.include?(id)
          @ids.delete(id)
        else
          @ids << id unless @ids.include?(id)
        end
        if ArchiBIM.instance_variable_get(:@dialog)&.visible?
          dialog=ArchiBIM.instance_variable_get(:@dialog)
          dialog.execute_script("window.ArchiBIM.setOpeningSelection(#{JSON.generate(@ids)})")
        end
        Sketchup.status_text="Selected #{@ids.length} hosted opening(s). Edit in Openings tab; Shift-click to add."
        view.invalidate
      end

      def onRButtonDown(flags,x,y,view)
        onLButtonDown(flags,x,y,view)
      end

      def onCancel(_reason,view)
        Sketchup.active_model.select_tool(nil)
        view.invalidate
      end

      def draw(view)
        @ids.each do |id|
          begin
            wall,data,opening=ArchiBIM.opening_selection(id)
            OpeningFocusTool.new(wall,data,opening).draw(view)
          rescue StandardError
            next
          end
        end
      end
    end
  end
end
