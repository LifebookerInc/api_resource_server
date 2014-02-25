module ApiResourceServer
  module Model

    extend ActiveSupport::Concern

    included do |klass|
      klass.class_attribute :protected_associations; klass.protected_associations = []
      klass.class_attribute :virtual_attributes; klass.virtual_attributes = []
      klass.class_attribute :private_attribute_names; klass.private_attribute_names = []
      klass.class_attribute :attribute_typecasts; klass.attribute_typecasts = {}

      klass.class_attribute :scope_definition
      klass.scope_definition = {}

      # specify the api interface
      klass.send(:acts_as_api)
      if klass.api_accessible(:public_api).blank?
        klass.api_accessible(:public_api) do |t|
          # we should really have the id here
          t.add(:id)
          (klass.public_attribute_names + klass.protected_attribute_names).each do |column|
            t.add(column)
          end
        end
      end
      # include routing
      klass.send(:include, Rails.application.routes.url_helpers) if defined?(Rails)
      # add scope protection behavior
      class << klass
        alias_method_chain :scope, :resource_definition_addition
      end

      if klass.api_accessible(:admin_api).blank?
        klass.api_accessible(:admin_api, :extend => :public_api) do |template|
          true
        end
      end
    end

    ASSOCIATION_TYPES = [:has_many, :has_one, :belongs_to]

    module ClassMethods

      # adds any available scopes to the scope
      # passed in
      #
      # @example
      #   class MyController < ActionController::Base
      #     # GET /my_resources.json
      #     def index
      #       @my_resources = MyResource.add_scopes(params)
      #     end
      #   end
      #
      # @param params [Hash]
      # @param scope [ActiveRecord::Relation]
      # @return [ActiveRecord::Relation]

      def add_scopes(params, scope = self.scoped)
        params = params.with_indifferent_access

        # add any type parameters
        scope = self.add_type_filter(params, scope)
        # add our static scopes
        scope = self.add_static_scopes(params, scope)
        scope = self.add_dynamic_scopes(params, scope)
        scope = self.add_pagination(params, scope)
      end

      # adds scopes that don't take any parameters to the scope
      # passed in
      #
      # @example
      #   class MyController < ActionController::Base
      #     # GET /my_resources.json
      #     def index
      #       @my_resources = MyResource.add_static_scopes(params)
      #     end
      #   end
      #
      # @param params [Hash]
      # @param scope [ActiveRecord::Relation]
      # @return [ActiveRecord::Relation]
      def add_static_scopes(params, scope = self.scoped)
        scope.klass.static_scopes.each do |scope_name|
          if params[scope_name].present?
            scope = scope.send(scope_name)
          end
        end
        # special case for ids
        if params[:ids].present?
          scope = scope.where(id: params[:ids])
        end
        scope
      end

      def add_type_filter(params, scope)
        return scope unless params[:type].present?

        # get the class - rescuing an invalid class name
        begin
          klass = params[:type].constantize

          # if we have been given a class that is not a subclass
          # we should return the original scope

          unless self.descendants.include?(klass)
            lb_logger.error("#{klass} is not a descendant of #{self}")
            return scope
          end

          # merge in our old scope and return
          klass.scoped.merge(scope)
        rescue NameError => e
          lb_logger.error(e.message)
          lb_logger.error(e.backtrace.pretty_inspect)
          return scope
        end
      end

      # adds scopes that take parameters to the scope
      # passed in
      #
      # @param params [Hash]
      # @param scope [ActiveRecord::Relation]
      # @return [ActiveRecord::Relation]
      #
      # @example
      #   class MyController < ActionController::Base
      #     # GET /my_resources.json
      #     def index
      #       @my_resources = MyResource.add_static_scopes(params)
      #     end
      #   end
      def add_dynamic_scopes(params, scope = self.scoped)
        scope.klass.dynamic_scopes.each_pair do |scope_name, arg_def|

          # skip scopes that are not defined
          next if params[scope_name].blank?

          # now apply the arguments
          args_to_pass = []

          # arg def tells us which args are required
          arg_def.each_pair do |arg_name, arg_type|
            case arg_type.to_sym
            # this argument is required
            when :req
              args_to_pass << params[scope_name][arg_name]
            when :opt
              unless params[scope_name][arg_name].nil?
                args_to_pass << params[scope_name][arg_name]
              end
            when :rest
              args_to_pass.concat(params[scope_name][arg_name] || [])
            end
          end

          # actually apply the scope
          scope = scope.send(scope_name, *args_to_pass)
        end

        # return the final scope
        scope
      end

      #
      # Add pagination if it is supplied in the params
      #
      # @param  params [Hash]
      # @param  scope = self.scoped [ActiveRecord::Relation]
      #
      # @return [ActiveRecord::Relation]
      def add_pagination(params, scope = self.scoped)
        if params[:page] || params[:per_page]
          scope = scope.paginate(
            page: params[:page] || 1,
            per_page: params[:per_page] || 20
          )
        end
        return scope
      end

      #
      # Make a given attribute or set of attributes
      #
      # @param  *attrs_to_expose [String, Symbol] Attributes to change
      #
      # @return [Boolean] true
      def make_public(*attrs_to_expose)
        self.protected_attributes.reject! { |protected_attr|
          attrs_to_expose.collect(&:to_s).include?(protected_attr)
        }
        true
      end

      #
      def resource_definition(reload = false)
        # memoized
        return @resource_definition if @resource_definition && !reload
        @resource_definition = {
          :attributes => {
            :public => self.typecast_fields(
              self.public_attribute_names.sort
            ),
            # there are some default protected fields (e.g. type) that we don't want to include unless they are real columns
            :protected => self.typecast_fields(
              self.protected_attribute_names.sort
            )
          },
          :associations => {},
          :scopes => {}
        }

        # should start with blank hashes
        ASSOCIATION_TYPES.each do |k|
          @resource_definition[:associations][k] = {}
        end
        # set up the associations
        self.reflect_on_all_associations.each do |assoc|
          next if self.protected_association?(assoc) || !ASSOCIATION_TYPES.include?(assoc.macro)
          @resource_definition[:associations][assoc.macro][assoc.name] = assoc.options.select{|k,v| [:class_name, :foreign_key].include?(k)}
        end

        # if we are using ApiResource, we also have remote associations
        if self.respond_to?(:related_objects)
          ASSOCIATION_TYPES.each do |k|
            next if self.related_objects["#{k}_remote"].blank?
            self.related_objects["#{k}_remote"].each_pair do |name, opts|
              @resource_definition[:associations][k.to_sym][name.to_sym] = opts.is_a?(Hash) ? opts : {}
            end
          end
        end

        # add in our scope definition
        @resource_definition[:scopes] = self.scope_definition
        @resource_definition
      end

      # set up a regular scope, but mark it as protected (not visible via the api)
      def protected_scope(*args)
        self.scope_without_resource_definition_addition(*args)
      end
      # set up a regular scope, making it visibule to the API
      def scope_with_resource_definition_addition(name, scope_options = {}, &block)
        # if it's a proc, we figure out its parameters
        if scope_options.is_a?(Proc)
          self.scope_definition = self.scope_definition.merge(
            name.to_sym => self.get_scope_parameters(scope_options)
          )
          # otherwise, we just say name => true
        else
          self.scope_definition = self.scope_definition.merge(
            name.to_sym => {}
          )
        end
        self.scope_without_resource_definition_addition(name, scope_options, &block)
      end

      # names for the public API
      def public_attribute_names
        attrs = (self.virtual_attributes + self.column_names + self.association_attributes).map(&:to_sym).uniq
        attrs -= self.protected_attributes.to_a.map(&:to_sym)
        attrs.uniq
      end

      def virtual_attribute(*attributes)
        opts = attributes.extract_options!

        attributes.flatten!
        self.virtual_attributes += attributes
        attributes.each do |attr|

          if opts.present?
            self.attribute_typecasts[attr.to_sym] ||= opts[:type]
          end

          if !self.public_instance_methods.include?(attr.to_sym) &&
            opts[:do_not_define_method] != true

            attr_reader attr
          end

          if !self.public_instance_methods.include?("#{attr}=".to_sym) &&
            opts[:do_not_define_method] != true

            attr_writer attr
          end

          if opts[:do_not_define_method] != true
            self.modify_api_fields(:public_api, :admin_api) do |t|
              t.add(attr)
            end
          end
        end
        # if self.respond_to?(:api_accessible_public_api)
        #   hsh = attributes.inject({}) {|h, a| h.merge({a => a})}
        #   self.api_accessible_public_api.merge!(hsh)
        # end
      end

      def alias_attribute_with_remove(new_name, old_name)
        alias_attribute(new_name, old_name)
        attr_private(old_name)
      end

      # override alias_attribute to
      def alias_attribute(new_name, old_name)
        super(new_name, old_name)
        virtual_attribute(new_name)
        # if we have an _id at the end, assume it's an association too
        # alias_attribute :abc_id, :test_id
        #
        # def abc(*args)
        #   self.send(:abc, *args)
        # end
        # def abc=(*args)
        #   self.send(:abc=, *args)
        # end
        if new_name.to_s =~ /_id$/ && old_name.to_s =~ /_id$/
          if self.instance_methods.include?("#{old_name.to_s.gsub(/\_id$/,'')}".to_sym)
            self.class_eval <<-EOE, __FILE__, __LINE__ + 1
            def #{new_name.to_s.gsub(/\_id$/, '')}(*args)
              self.send("#{old_name.to_s.gsub(/\_id$/, '')}", *args)
            end
            EOE
          end
          if self.instance_methods.include?("#{old_name.to_s.gsub(/\_id$/,'')}=".to_sym)
            self.class_eval <<-EOE, __FILE__, __LINE__ + 1
            def #{new_name.to_s.gsub(/\_id$/, '')}=(*args)
              self.send("#{old_name.to_s.gsub(/\_id$/, '')}=", *args)
            end
            EOE
          end
        end
      end

      # since we define private attributes as part of the protected_attributes array, we need to
      # do this by removing public and private - everything left is protected
      def protected_attribute_names
        (self.virtual_attributes.map(&:to_sym) + self.column_names.map(&:to_sym) - self.public_attribute_names.map(&:to_sym) - self.private_attribute_names.map(&:to_sym))
      end
      # remove this from the public api template if it's there
      def attr_private(*args)
        self.modify_api_fields(:public_api, :admin_api) do |template|
          args.flatten.each do |col|
            template.remove(col.to_sym)
          end
        end
        self.private_attribute_names += args.flatten.map(&:to_sym)
        attr_protected(*args)
      end

      protected

        # list of all scopes that take an argument
        # @return [Hash<Symbol, Hash>]
        def dynamic_scopes
          scopes = self.resource_definition[:scopes].select { |k, v| v.present? }
        end

        # list of all scopes that don't take any arguments
        def static_scopes
          scopes = self.resource_definition[:scopes].select { |k, v| v.blank? }.keys
          scopes | [:first, :last, :all]
        end

        # determine if fields are in the db and, if so, typecast them for
        # the resource definition
        def typecast_fields(field_names)
          # types of times
          time_classes = [Time, DateTime, ActiveSupport::TimeWithZone]

          field_names.map do |field|
            # copy so we don't modify it
            klone = field.to_sym

            if self.attribute_typecasts[klone].present?
              if time_classes.include?(self.attribute_typecasts[klone])
                klone = [klone.to_sym, :time]
              elsif self.attribute_typecasts[klone] == Date
                klone = [klone.to_sym, :date]
              else
                klone = [klone.to_sym, self.attribute_typecasts[klone].to_s.downcase.to_sym]
              end
            elsif self.column_names.include?(klone.to_s)
              col = self.columns.detect{|c| c.name.to_s == klone.to_s}
              if col.klass == Date
                klone = [klone.to_sym, :date]
              elsif time_classes.include?(col.klass)
                klone = [klone.to_sym, :time]
              else
                klone = [klone.to_sym, col.type]
              end
            end
            klone
          end
        end

        # nodoc
        # Helper to extract scope options into something usable in a resource definition
        def get_scope_parameters(proc)
          params = {}
          proc.parameters.each do |type, param|
            params[param] = type
          end
          params
        end

        # add fields to multiple api templates at once
        def modify_api_fields(*templates, &block)
          templates.flatten.each do |template|
            self.api_accessible(template, &block)
          end
        end

        # attributes created by associations
        def association_attributes
          [].tap do |attrs|
            self.reflect_on_all_associations.each do |assoc|
              next if self.protected_association?(assoc)
              attrs << ("#{assoc.name.to_s.singularize}_id#{'s' if assoc.collection?}").to_sym
            end
          end
        end
        # is this association protected?
        def protected_association?(assoc)
          self.protected_associations.include?(assoc.name)
        end
        # definition of all scopes
        def scope_definition
          @scope_definition ||= {}
        end

      private
        ASSOCIATION_TYPES.each do |type|
          self.module_eval <<-EOE, __FILE__, __LINE__ + 1
          def #{type}(*args)
            opts = args.extract_options!
            if opts.delete(:protected) == true
              self.protected_associations << args.first.to_sym
            end
            super(*args, opts)
          end
          EOE
        end
    end

    # get resource definition for the class from the instance too
    def resource_definition(reload = false)
      self.class.resource_definition(reload)
    end

    # get around mass-assignment restrictions if desired/allowed
    def update_attributes_with_protected(attrs, allow_protected = false)
      return self.update_attributes(attrs) unless allow_protected
        attrs.each_pair do |k,v|
          self.send("#{k}=", v)
        end
        return self.save
    end

  end
end