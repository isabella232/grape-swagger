module GrapeSwagger
  module DocMethods
    class MoveParams
      class << self
        def to_definition(paths, definitions)
          @definitions = definitions
          find_post_put(paths) do |path|
            find_definition_and_params(path)
          end
        end

        def find_post_put(paths)
          paths.each do |x|
            found = x.last.select { |y| move_methods.include?(y) }
            yield found unless found.empty?
          end
        end

        def find_definition_and_params(path)
          path.keys.each do |verb|
            params = path[verb][:parameters]

            next if params.nil?
            next unless should_move?(params)

            unify!(params)

            status_code = GrapeSwagger::DocMethods::StatusCodes.get[verb.to_sym][:code]
            response = path[verb][:responses][status_code]
            referenced_definition = parse_model(response[:schema]['$ref'])

            name = build_definition(referenced_definition, verb)
            move_params_to_new(name, params)

            @definitions[name][:description] = path[verb][:description]
            path[verb][:parameters] << build_body_parameter(response.dup, name)
          end
        end

        def move_params_to_new(name, params)
          properties = {}
          definition = @definitions[name]

          nested_definitions(name, params, properties)

          params.dup.each do |param|
            next unless movable?(param)

            name = param[:name].to_sym
            properties[name] = {}

            properties[name].tap do |x|
              property_keys.each do |attribute|
                x[attribute] = param[attribute] unless param[attribute].nil?
              end
            end

            properties[name][:readOnly] = true unless deletable?(param)
            params.delete(param) if deletable?(param)

            definition[:required] << name if deletable?(param) && param[:required]
          end

          definition.delete(:required) if definition[:required].empty?
          definition[:properties] = properties
        end

        def nested_definitions(name, params, properties)
          loop do
            nested_name = params.bsearch { |x| x[:name].include?('[') }
            return if nested_name.nil?

            nested_name = nested_name[:name].split('[').first

            nested, = params.partition { |x| x[:name].start_with?("#{nested_name}[") }
            nested.each { |x| params.delete(x) }
            nested_def_name = GrapeSwagger::DocMethods::OperationId.manipulate(nested_name)
            def_name = "#{name}#{nested_def_name}"
            properties[nested_name] = { '$ref' => "#/definitions/#{def_name}" }

            prepare_nested_names(nested)
            build_definition(def_name)

            move_params_to_new(def_name, nested)
          end
        end

        private

        def build_body_parameter(response, name = false)
          body_param = {}
          body_param.tap do |x|
            x[:name] = parse_model(response[:schema]['$ref'])
            x[:in] = 'body'
            x[:required] = true
            x[:schema] = { '$ref' => response[:schema]['$ref'] } unless name
            x[:schema] = { '$ref' => "#/definitions/#{name}" } if name
          end
        end

        def build_definition(name, verb = nil)
          name = "#{verb}Request#{name}" if verb
          @definitions[name] = { type: 'object', properties: {}, required: [] }

          name
        end

        def prepare_nested_names(params)
          params.each do |param|
            param.tap do |x|
              name = x[:name].partition('[').last.sub(']', '')
              name = name.partition('[').last.sub(']', '') if name.start_with?('[')
              x[:name] = name
            end
          end
        end

        def unify!(params)
          params.each do |param|
            param[:in] = param.delete(:param_type) if param.key?(:param_type)
            param[:in] = 'body' if param[:in] == 'formData'
          end
        end

        def parse_model(ref)
          ref.split('/').last
        end

        def move_methods
          [:post, :put, :patch]
        end

        def property_keys
          [:type, :format, :description, :minimum, :maximum, :items]
        end

        def movable?(param)
          return true if param[:in] == 'body' || param[:in] == 'path'
          false
        end

        def deletable?(param)
          return true if movable?(param) && param[:in] == 'body'
          false
        end

        def should_move?(params)
          !params.select { |x| x[:in] == 'body' || x[:param_type] == 'body' }.empty?
        end
      end
    end
  end
end