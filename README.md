# ApiResourceServer

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'api_resource_server'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install api_resource_server

## Usage

ApiResourceServer::Model is used to set up the Resource Definition for
an ActiveRecord resource.  The Resource Definition is used by ApiResource
to determine which attributes, associations and scopes the Resource has.

### Sample Resource Definition

    # Model with fields
    class Person < ActiveRecord::Base

      # needs to include this module
      include ApiResourceServer::Model

      # attributes :active, :first_name, :last_name, :birthday

      # associations
      belongs_to :state
      has_many :weapons

      # scopes
      scope :active, where(active: true)
      scope :born_on, -> day { where(birthday: day) }
    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     public: [
    #       ["active", "boolean"],
    #       ["birthday", "string"],
    #       ["first_name", "string"],
    #       ["last_name", "string"],
    #       ["state_id", "integer"],
    #       ["weapon_ids", "array"]
    #     ],
    #     protected: [
    #       ["created_at", "time"],
    #       ["id", "integer"],
    #       ["updated_at", "time"],
    #     ]
    #   },
    #   associations: {
    #     belongs_to: { state: {} },
    #     has_many: { weapons: {} }
    #   },
    #   scopes: {
    #     active: {},
    #     born_on: { day: :req }
    #   }
    # }

### Visibility

Database column attributes are public by default.  To make an attribute
protected use:

    class Person < ActiveRecord::Base
      attr_protected :first_name
    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     ...
    #     protected: [
    #       ...
    #       ["first_name", "string"]
    #        ...
    #     ]
    #     ...
    #   }
    # }

To remove an attribute from the resource definition entirely
use `attr_private`

    class Person < ActiveRecord::Base
      attr_private :first_name
    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     public: [
    #       ["active", "boolean"],
    #       ["birthday", "string"],
    #       ["last_name", "string"]
    #     ],
    #     protected: [
    #       ["created_at", "time"],
    #       ["id", "integer"],
    #       ["updated_at", "time"],
    #     ]
    #   }
    #   ...
    # }

To remove an association pass the option `protected: true`
when defining the association

    # Model with fields
    class Person < ActiveRecord::Base

      # associations
      belongs_to :state, protected: true
    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     public: [
    #       ["active", "boolean"],
    #       ["birthday", "string"],
    #       ["first_name", "string"],
    #       ["last_name", "string"],
    #       # no state_id
    #       ["weapon_ids", "array"]
    #     ],
    #   ...
    #   associations: {
    #     has_many: { weapons: {} }
    #   },
    #   ...
    # }

To remove a scope use `protected_scope` instead of `scope`
    class Person < ActiveRecord::Base
      protected_scope :active, where(active: true)
    end

    Person.resource_definition
    # => {
    #   ...
    #   scopes: {
    #     born_on: { day: :req }
    #   }
    # }

### Non-database attributes

`attr_accessor` or other attribute methods can be exposed via
`virtual_attribute`.  Optionally, you can specify the type

    # Model with fields
    class Person < ActiveRecord::Base

      virtual_attribute :foo, type: String

      def foo=()
        # ...
      end

      def foo
        # ...
      end

    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     public: [
    #     ...
    #       ["foo", "string"]
    #     ...
    #     ]
    #   }
    #   ...
    # }

### Renaming attributes

We override `alias_attribute` to also remove the old attribue and
add the new attribute to our resource definition

    # Model with fields
    class Person < ActiveRecord::Base
      alias_attribute :first_name, :nickname
    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     public: [
    #     ...
    #       # first_name is removed
    #       ["nickname", "string"]
    #     ...
    #     ]
    #   }
    #   ...
    # }

### Exposing an instance method without a writer

If you want to expose data but not allow a writer method, you can combine
`virtual_attribute` and `attr_protected`

    # Model with fields
    class Person < ActiveRecord::Base

      virtual_attribute :foo, type: String
      attr_protected :foo

    end

    Person.resource_definition
    # => {
    #   attributes: {
    #     protected: [
    #     ...
    #       ["foo", "string"]
    #     ...
    #     ]
    #   }
    #   ...
    # }

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
