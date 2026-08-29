# frozen_string_literal: true

module ::Maskid
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace Maskid
    config.autoload_paths << File.join(config.root, "lib")
  end
end
