# frozen_string_literal: true
require 'json'
require 'fileutils'
require 'tmpdir'
require 'time'

module SSDigitalLab
  module ArchiBIM
    # Readable diagnostic trace for user-submitted SketchUp tests.
    # No camera images, model geometry, or personal files are collected.
    module Diagnostics
      module_function

      def folder
        @folder ||= File.join(Dir.tmpdir, 'ArchiBIM', 'logs')
        FileUtils.mkdir_p(@folder)
        @folder
      end

      def path
        File.join(folder, 'archibim_session.jsonl')
      end

      def log(event, details = {})
        if File.file?(path) && File.size(path) > 3_000_000
          archive = File.join(folder, 'archibim_previous.jsonl')
          File.delete(archive) if File.exist?(archive)
          File.rename(path, archive)
        end
        record = { 'at' => Time.now.iso8601, 'version' => ArchiBIM::VERSION,
                   'event' => event.to_s, 'details' => details }
        File.open(path, 'a:UTF-8') { |f| f.puts(JSON.generate(record)) }
      rescue StandardError => error
        warn("ArchiBIM diagnostics: #{error.class}: #{error.message}")
      end

      def error(event, exception)
        log('error', { 'during' => event.to_s, 'class' => exception.class.name,
                       'message' => exception.message,
                       'trace' => exception.backtrace&.first(12) || [] })
      end

      def export(model, elements)
        destination = UI.savepanel('Save ArchiBIM testing log', nil, 'ArchiBIM_Testing_Log.txt')
        return nil if destination.nil?
        report = {
          'archibim_version' => ArchiBIM::VERSION,
          'sketchup_version' => Sketchup.version,
          'levels' => ArchiBIM.levels,
          'active_level' => ArchiBIM.current_level['id'],
          'model_units' => model.options['UnitsOptions']['LengthUnit'],
          'elements' => elements.map do |group, data|
            t = group.transformation
            { 'id' => data['id'], 'kind' => data['kind'], 'level_id' => data['level_id'],
              'length' => data['length'], 'width' => data['width'], 'height' => data['height'],
              'scales' => [t.xaxis.length.to_f, t.yaxis.length.to_f, t.zaxis.length.to_f],
              'openings' => data.fetch('openings', []).length }
          end
        }
        File.open(destination, 'w:UTF-8') do |file|
          file.puts('ArchiBIM Testing Diagnostics')
          file.puts(JSON.pretty_generate(report))
          file.puts("\n--- Session event log (JSONL) ---")
          file.write(File.read(path, encoding: 'UTF-8')) if File.exist?(path)
        end
        destination
      end
    end
  end
end
