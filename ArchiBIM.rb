# frozen_string_literal: true
# ArchiBIM: standalone SketchUp extension loader
require 'sketchup.rb'
require 'extensions.rb'

module SSDigitalLab
  module ArchiBIM
    unless defined?(@extension_registered) && @extension_registered
      extension = SketchupExtension.new('ArchiBIM - Architectural BIM', 'archibim/main')
      extension.description = 'Parametric building elements, hosted openings, levels, schedules and IFC handoff.'
      extension.version = '0.7.0'
      extension.creator = 'SS Digital Lab'
      extension.copyright = '2026 SS Digital Lab'
      Sketchup.register_extension(extension, true)
      @extension_registered = true
    end
  end
end
