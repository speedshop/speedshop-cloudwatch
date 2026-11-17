load File.join(
  Gem.loaded_specs.fetch("solid_queue").full_gem_path,
  "lib/generators/solid_queue/install/templates/db/queue_schema.rb"
)
