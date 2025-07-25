# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

require 'sprockets/railtie'

# TODO(plural): See if there is a different solution here.
# Requied by Graphiti but not included in their for top-level Gem for some reason.
require 'ostruct'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NrdbApi
  class Application < Rails::Application # rubocop:disable Style/Documentation
    routes.default_url_options[:host] = ENV.fetch('HOST', 'http://localhost:3100')

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    config.eager_load_paths << Rails.root.join('lib')

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Prefix for Printing images.
    config.x.printing_images.nrdb_classic_prefix = 'https://card-images.netrunnerdb.com/v2'

    config.encoding = 'utf-8'
  end
end
