# frozen_string_literal: true
require 'csv'
module SSDigitalLab
  module ArchiBIM
    module OpeningSchedules
      extend self
      HEADERS=%w[mark level host_wall kind width_mm height_mm sill_mm panels operation hinge swing door_style handle glass_mm transom transom_height_mm area_m2 count opening_id].freeze
      def records
        items=[]
        ArchiBIM.elements.each do |_,wall|
          next unless wall['kind']=='wall'
          level=ArchiBIM.levels.find{|l|l['id']==wall['level_id']}
          Array(wall['openings']).each do |o|
            kind=o['kind']
            items << {
              'opening_id'=>o['id'],'level'=>level ? level['name'] : 'Unknown',
              'host_wall'=>wall['name'],'kind'=>kind,'width_mm'=>o['width'],
              'height_mm'=>o['height'],'sill_mm'=>o['sill'],
              'panels'=>o['panels'] || 1, 'operation'=>o['operation'] || '',
              'hinge'=>o['hinge'] || '', 'swing'=>o['swing'] || '',
              'door_style'=>o['style'] || '', 'handle'=>o['handle'] || '',
              'glass_mm'=>o.fetch('glass_thickness',3.0),
              'transom'=>o.fetch('transom',false),
              'transom_height_mm'=>o.fetch('transom_height',0),
              'area_m2'=>(o['width'].to_f*o['height'].to_f/1_000_000.0).round(4),
              'count'=>1
            }
          end
        end
        # Same size, style, frame, transom and level receives the same mark.
        buckets={}
        items.sort_by{|o|[o['kind'],o['level'],o['width_mm'].to_f,o['height_mm'].to_f]}.each do |o|
          key=%w[level kind width_mm height_mm sill_mm panels operation hinge swing door_style handle glass_mm transom transom_height_mm].map{|field|o[field]}
          buckets[key] ||= (o['kind']=='window' ? "W" : o['kind']=='sliding_door' ? 'SD' : 'D')+"%03d" % (buckets.size+1)
          o['mark']=buckets[key]
        end
        items
      end

      def export
        path=UI.savepanel('Export door and window schedule',nil,'ArchiBIM_Door_Window_Schedule.csv')
        return nil unless path
        rows=records
        CSV.open(path,'w:UTF-8',write_headers:true,headers:HEADERS) do |csv|
          rows.each{|r|csv << HEADERS.map{|h|r[h]}}
        end
        Diagnostics.log('opening_schedule_export',{count:rows.length,path:path})
        UI.messagebox("Door/window schedule exported (#{rows.length} opening instances).\n#{path}")
        path
      end
    end
  end
end
