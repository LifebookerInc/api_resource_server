# encoding: utf-8
require 'spec_helper'

module ApiResourceServer

  describe Model do

    before(:all) do

      ActiveRecord::Base.connection.create_table(:posts, force: true) do |t|
        t.string :title
        t.text :body
        t.integer :user_id
        t.string :protected_field
        t.string :private_field
        t.timestamps
      end

      ActiveRecord::Base.connection.create_table(:users, force: true) do |t|
        t.string :name
        t.date :bday
        t.string :type
        t.timestamps
      end

      ActiveRecord::Base.connection.create_table(:comments, force: true) do |t|
        t.text :body
        t.integer :post_id
        t.timestamps
        t.string :type
      end

      Post.class_eval do
        reset_column_information
        include ApiResourceServer::Model

        has_many :comments
        belongs_to :user

        belongs_to_remote :remote_comment

        attr_protected :protected_field
        attr_private :private_field
        virtual_attribute :v_field
        virtual_attribute :v_field_no_definition,
          do_not_define_method: true

        scope :user_id_scope, lambda { |user_id|
          where(user_id: user_id)
        }
        scope :vararg_scope, lambda { |*ids|
          where(['id IN (?)', args.flatten])
        }
        scope :two_param_scope, lambda { |id1,id2|
          where(['id IN (?)', [id1, id2]])
        }
        scope :no_param_scope, where('x = 1')
        scope :empty_lambda_scope, lambda{ where(['date > ?', Date.today])}
        scope :optional_arg_scope, lambda{|a, b = 5|}

        protected_scope :nonsense, lambda{|id, test| where(user_id: id)}
      end

      Object.const_set('Comment', Class.new(ActiveRecord::Base))
      Comment.class_eval do
        include ApiResourceServer::Model
        belongs_to :post
      end

      Object.const_set('RemoteComment', Comment)


      Object.const_set('User', Class.new(ActiveRecord::Base))
      User.class_eval do
        include ApiResourceServer::Model
        has_many :posts

        attr_protected(:updated_at)

        scope :by_name, lambda { |name|
          where(name: name)
        }

      end

      Object.const_set('Admin', Class.new(User))
      Admin.class_eval do
        scope :bday, lambda { |bday|
          where(bday: bday)
        }
      end

    end

    context '.add_scopes' do

       it 'adds all types of scopes to the supplied collection' do

        scope = Post.scoped

        scope.expects(:user_id_scope)
          .with('1')
          .returns(scope)

        scope.expects(:two_param_scope)
          .with('1', '2')
          .returns(scope)

        scope.expects(:vararg_scope)
          .with('1', '2', '3')
          .returns(scope)

        scope.expects(:optional_arg_scope)
          .with('req')
          .returns(scope)

        Post.add_scopes(
          {
            user_id_scope: { user_id: '1' },
            two_param_scope: {
              id1: '1',
              id2: '2'
            },
            vararg_scope: { ids: %w{1 2 3} },
            optional_arg_scope: { a: 'req' }
          },
          scope
        )

      end

      context 'Custom type' do

        it 'applies a filter on the type when a type key is passed in' do
          scope = User.add_scopes(type: 'Admin')
          expect(scope.where_values_hash[:type]).to eql(['Admin'])
        end

        it 'handles invalid class names' do
          expect {
            scope = User.add_scopes(type: 'InvalidClass')
          }.not_to raise_error
        end

        it 'merges with the scope that was passed in' do
          scope = User.add_scopes({ type: 'Admin' }, User.where(name: 'Dan'))
          expect(scope.where_values_hash[:name]).to eql('Dan')
          expect(scope.where_values_hash[:type]).to eql(['Admin'])
        end

        it 'does not apply a scope unless a descendant class is supplied' do
          original_scope = User.where(name: 'Dan')
          scope = User.add_scopes({ type: 'Post' }, original_scope)

          # shouldn't do anything
          expect(scope).to eql(original_scope)
        end

      end




      it 'adds pagination' do

        scope = Post.scoped

        scope.expects(:paginate)
          .with(page: 3, per_page: 20)
          .returns(scope)

        Post.add_scopes({ page: 3, per_page: 20 }, scope)

      end


    end

    context '.add_static_scopes' do

      it 'should add static scopes to the supplied collection' do
        scope = Post.scoped
        scope.expects(
          no_param_scope: scope,
          empty_lambda_scope: scope
        )
        scope.expects(:two_param_scope).never
        scope.expects(:where).with(id: [1, 2])

        params = {
          no_param_scope: true,
          empty_lambda_scope: true,
          two_param_scope: true,
          ids: [1, 2]
        }

        Post.add_static_scopes(params, scope)
      end

    end

    it 'should automatically include all public attributes in the public hash for APIs' do
      Post.resource_definition(true)[:attributes][:public].should include [:body, :text]
      Post.resource_definition(true)[:attributes][:public].should_not include :protected_field
    end

    it 'should include id methods for associations in the public attributes' do
      Post.resource_definition(true)[:attributes][:public].should include :comment_ids
    end

    it 'should typecast its values in both its public and
      protected attributes' do

      attr = User.resource_definition(true)[:attributes]

      attr[:public].should include [:created_at, :time]
      attr[:public].should include [:bday, :date]
      attr[:protected].should include [:updated_at, :time]

      (attr[:public] | attr[:protected]).each{|at|
        if at.instance_of?(Array)
          if User.column_names.include?(at.first.to_s) || User.attribute_typecasts[at.first.to_s].present?
            at.count.should eql 2
          end
        end
      }

    end

    it 'should try to typecast attributes for which there is no
      column match using a typecast store' do

      User.class_eval do
        virtual_attribute(:virtual_time, {type: DateTime})
        virtual_attribute(:virtual_time_with_zone, {type: ActiveSupport::TimeWithZone})
        virtual_attribute(:virtual_date, {type: Date})
      end

      attr = User.resource_definition(true)[:attributes]
      attr[:public].should include [:virtual_time, :time]
      attr[:public].should include [:virtual_time_with_zone, :time]
      attr[:public].should include [:virtual_date, :date]

    end

    it "should try to use a custom typecast before a column default" do

      User.class_eval do
        virtual_attribute(:name, :type => :integer)
      end

      attrs = User.resource_definition(true)[:attributes]
      attrs[:public].should include [:name, :integer]
      attrs[:public].should_not include [:name, :string]

    end


    context 'Routes' do
      it 'should include routes in the model' do
        Post.included_modules.should include Rails.application.routes.url_helpers
      end
    end

    context 'Virtual Attributes' do

      after(:all) do
        # remove abc from public api
        Post.class_eval do
          self.modify_api_fields(:public_api, :admin_api) do |template|
            template.remove(:abc)
          end
        end
      end

      it 'should automatically include all virtual attributes in the public hash for APIs' do
        Post.resource_definition(true)[:attributes][:public].should include :v_field
      end

      it 'should automatically assign setters and getters for virtual attributes' do
        Post.public_instance_methods.should include :v_field
        Post.public_instance_methods.should include :v_field=
      end

      it 'should not assign setters and getters for virtual attributes when given the
        do_not_define_method option' do
        Post.public_instance_methods.should_not include :v_field_no_definition
        Post.public_instance_methods.should_not include :v_field_no_definition=
      end

      it 'should not overwrite existing accessors when virtual attributes are added' do
        Post.class_eval do
          def abc
            @abc_called = true
          end
          def abc=(x)
            @abc_equals_called = true
          end
          virtual_attribute(:abc)
        end
        p = Post.new
        p.abc
        p.abc = 100
        p.instance_variable_get(:@abc_called).should be true
        p.instance_variable_get(:@abc_equals_called).should be true
      end

      it 'should be able to include virtual attributes as protected attributes' do
        Post.class_eval do
          virtual_attribute(:protected_virtual_attr)
          attr_protected(:protected_virtual_attr)
        end
        Post.resource_definition(true)[:attributes][:protected].should include :protected_virtual_attr
        Post.resource_definition(true)[:attributes][:public].should_not include :protected_virtual_attr
      end

    end

    it 'should automatically include all of the protected attributes in the protected attributes for the APIs' do
      Post.resource_definition(true)[:attributes][:protected].should_not include [:body, :text]
      Post.resource_definition(true)[:attributes][:protected].should include [:protected_field, :string]
    end
    it 'should automatically remove all private attributes from both the public and protected hashes' do
      Post.resource_definition(true)[:attributes][:public].should_not include [:private_field, :string]
      Post.resource_definition(true)[:attributes][:protected].should_not include [:private_field, :string]
    end

    it 'should automatically include all associations in the associations hash for the APIs' do
      Post.resource_definition(true)[:associations][:has_many].keys.should include :comments
      Post.resource_definition(true)[:associations][:belongs_to].keys.should include :user
    end

    it 'should include belongs_to_remote associations in the belongs_to definition' do
      Post.resource_definition(true)[:associations][:belongs_to].keys.should include :remote_comment
    end


    it 'should allow the user to specify associations that are not included in the hash for the APIs' do
      Comment.resource_definition(true)[:associations][:belongs_to].keys.should include :post
      Comment.send(:belongs_to, :post, protected: true)
      Comment.resource_definition(true)[:associations][:belongs_to].keys.should_not include :post
    end
    it 'should automatically include scopes if they are defined' do
      Post.resource_definition(true)[:scopes].keys.should include :user_id_scope
    end
    it 'should allow the user to specify scopes that are not included in the hash for the APIs' do
      Post.resource_definition(true)[:scopes].keys.should_not include :nonsense
    end
    it 'should create proper arguments for scopes' do
      Post.resource_definition(true)[:scopes][:user_id_scope].should eql({user_id: :req})
      Post.resource_definition(true)[:scopes][:empty_lambda_scope].should eql({})
      Post.resource_definition(true)[:scopes][:vararg_scope].should eql({ids: :rest})
      Post.resource_definition(true)[:scopes][:two_param_scope].should eql({id1: :req, id2: :req})
      Post.resource_definition(true)[:scopes][:no_param_scope].should eql({})
      Post.resource_definition(true)[:scopes][:optional_arg_scope].should eql({a: :req, b: :opt})
    end

    it 'should ignore association options other than class_name and foreign_key' do
      Post.class_eval do
        has_many :comments_with_options, class_name: 'Comment', foreign_key: 'post_id', dependent: :delete_all
      end

      Post.resource_definition(true)[:associations][:has_many][:comments_with_options].keys.sort.should eql [:class_name, :foreign_key].sort

    end

    context 'Aliasing attributes' do

      before(:each) do
        Post.delete_all
      end

      it 'should alias attributes' do
        Post.class_eval do
          alias_attribute :blahblah, :body
          alias_attribute :blah_id, :user_id
        end

        [:blah_id=, :blah=, :blah, :blah_id, :blahblah, :blahblah=].each do |m|
          Post.public_instance_methods.should include m
        end
      end

      it 'should accept attributes for aliased methods' do
        post = Post.create({title: 'Post', body: 'Body'})

        Post.class_eval do
          alias_attribute :name, :title
        end

        new_post_data = {name: 'New Post', body: 'New Body'}
        post.attributes = new_post_data

        post.title.should eql 'New Post'
      end
    end


    context 'Protected Attribute Updates' do
      it 'should allow for updates to protected attributes if the proper permissions are present' do
        p = Post.create(title: 'test', body: 'test')
        # this would be called as
        # p.update_attributes_with_protected(params[:post], current_user.has_permission?('super_user'))
        p.update_attributes_with_protected({protected_field: 'Test'}, true).should be true
        p.reload.protected_field.should eql 'Test'
      end
    end

    context '#resource_definition' do

      context 'Scopes' do

        it "has scopes from the parent class in the subclass" do

          expect(User.resource_definition[:scopes]).to have_key(:by_name)
          expect(Admin.resource_definition[:scopes]).to have_key(:by_name)

        end

        it 'does not have scopes from the subclass in the parent class' do

          expect(User.resource_definition[:scopes]).not_to have_key(:bday)
          expect(Admin.resource_definition[:scopes]).to have_key(:bday)

        end



      end

    end



    context 'ActsAsApi Integration' do
      it 'should include acts_as_api' do
        Post.included_modules.should include ActsAsApi::Base::InstanceMethods
      end

      it 'should auto-define public_api' do
        Post.new.as_api_response(:public_api).keys.sort.should eql [:blahblah, :blah_id, :body, :created_at, :id, :name, :protected_field, :protected_virtual_attr, :title, :updated_at, :user_id, :v_field].sort
      end

      it 'should auto-define admin_api' do
        Post.new.as_api_response(:admin_api).keys.sort.should eql [:blahblah, :blah_id, :body, :created_at, :id, :name, :protected_field, :protected_virtual_attr, :title, :updated_at, :user_id, :v_field].sort
      end

      it 'should automatically add fields to admin_api that have been manually added to public_api' do
        Post.class_eval do
          def new_method
            1
          end
          modify_api_fields(:public_api, :admin_api) do |template|
            template.add(:new_method)
          end
        end
        Post.new.as_api_response(:admin_api).keys.should include :new_method
      end
    end
  end
end
