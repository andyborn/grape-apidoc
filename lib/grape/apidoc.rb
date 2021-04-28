module Grape
  class Apidoc
    autoload :RakeTask, 'grape/apidoc/rake_task'
    autoload :TableFormat, 'grape/apidoc/table_format'

    FIELDS_TABLE = TableFormat.new([20, 10, 40]).freeze # Field, Type, Description

    def initialize(root_api_class = nil, output: $stdout)
      @api = root_api_class || detect_root_api_class
      @out = output
    end

    def write!
      write_entities! if defined?(Grape::Entity)
      write_routes!
    end

    private

    def detect_root_api_class
      # performance shortcut for https://github.com/bsm/grape-app/
      return Grape::App if defined?(Grape::App)

      # root api is the one with largest route count:
      Grape::API.descendants.max do |a, b|
        a.try(:routes)&.count <=> b.try(:routes)&.count
      end
    end

    def write_entities!
      @out.puts '# Entities'
      @out.puts

      @api.routes.filter_map(&:entity).uniq.sort_by(&:name).each do |entity|
        write_entity_header!(entity)
        @out.puts

        write_entity_fields!(entity)
        @out.puts
      end
    end

    def write_entity_header!(entity)
      @out.puts "## #{entity_name(entity)}"
    end

    def write_entity_fields!(entity)
      unless entity.documentation.present?
        @out.puts '*No fields exposed.*'
        return
      end

      @out.puts FIELDS_TABLE.format('Field', 'Type', 'Description')
      @out.puts FIELDS_TABLE.separator

      entity.documentation.each do |name, details|
        # Problem: it's pretty much impossible to match Entity to model to dig column types.
        # Need to either enforce some requirements for organizing API or give up.
        type, desc, = details.values_at(:type, :desc)
        type = "[#{type}]" if details[:is_array]
        @out.puts FIELDS_TABLE.format(name.to_s, type.to_s, desc.to_s)
      end
    end

    def write_routes!
      @out.puts '# Routes'
      @out.puts

      @api.routes.each do |route|
        write_route_header!(route)
        @out.puts

        # list items:
        write_route_retval!(route)
        write_route_security!(route)
        @out.puts

        write_route_params!(route)
        @out.puts
      end
    end

    def write_route_header!(route)
      method = route.request_method
      path = route.path
                  .sub(':version', route.version.to_s)
                  .sub('(.:format)', '')
      @out.puts "## #{method} #{path}"

      return unless route.description.present?

      @out.puts
      @out.puts route.description
    end

    def write_route_security!(route)
      security = route.settings.dig(:description, :security)
      return unless security.present?

      security_desc = security.map {|k, v| "#{k}=#{v.inspect}" }.join(' ')

      @out.puts "- **Security**: `#{security_desc}`"
    end

    def write_route_retval!(route)
      entity = route.try(&:entity)
      return unless entity

      array_prefix = 'List of ' if route.settings.dig(:description, :is_array)

      name = entity_name(entity)
      @out.puts "- **Returns**: #{array_prefix}[#{name}](##{identifier(name)})"
    end

    def write_route_params!(route)
      return unless route.params.present?

      @out.puts '**Parameters**:'
      @out.puts

      @out.puts FIELDS_TABLE.format('Parameter', 'Type', 'Description')
      @out.puts FIELDS_TABLE.separator

      route.params.each do |name, details|
        # route.params includes path params as well, like `id => ''`
        # (not a hash, like normal params):
        details = {} unless details.is_a?(Hash)

        # Problem: it's pretty much impossible to match Entity to model to dig column types.
        # Problem: it's not guaranteed that Entity exposures match params.
        # Need to either enforce some requirements for organizing API or give up.
        type = details[:type] || ''
        desc = details.except(:type).map {|k, v| "#{k}: #{v}" }.join(', ')
        @out.puts FIELDS_TABLE.format(name.to_s, type, desc)
      end
    end

    def identifier(str)
      str.downcase.gsub(/[^0-9a-z-]/, '-')
    end

    def entity_name(entity)
      entity.name.gsub(/(?:::)?Entity\Z/, '').gsub('::', ':')
    end
  end
end
