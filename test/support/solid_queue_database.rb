# frozen_string_literal: true

require "rails"
require "active_record"
require "solid_queue"

solid_queue_path = Gem.loaded_specs["solid_queue"].full_gem_path

models = Zeitwerk::Loader.new
models.push_dir(File.join(solid_queue_path, "app/models"))
models.setup

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
load File.join(solid_queue_path, "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
