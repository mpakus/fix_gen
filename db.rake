namespace :db do
  desc 'Create YML fixture from an existing table'
  task :fixture, [:table] => :environment do |_task, args|
    if args[:table].blank?
      puts 'rake db:fixture[table_name]'
      exit
    end
    write_to_file(args[:table])
    puts '---+++ done +++---'
  end

  def write_to_file(table)
    sql       = 'SELECT * FROM %s LIMIT 10'
    file_name = Rails.root.to_s << "/test/fixtures/#{table}.yml"
    if File.exist? file_name
      puts "sorry '#{file_name}' already exist"
      exit
    end

    File.open(file_name, 'w') do |file|
      data = ActiveRecord::Base.connection.select_all(sql % table)
      i = '000'
      file.write data.inject({}) { |hash, record|
        hash["#{table}_#{i.succ!}"] = record
        hash
      }.to_yaml
    end
  end

  desc 'Generate test from model'
  task :model_test, [:model] => :environment do |_task, args|
    if args[:model].blank?
      puts 'rake db:model_test[model]'
      exit
    end

    model = args[:model]
    klass = model.camelize.constantize

    file_name = Rails.root.to_s << "/test/models/#{klass.name.to_s.underscore}_test.rb"
    if File.exist? file_name
      puts "sorry '#{file_name}' already exist"
      exit
    end

    code  = generate_layout(
        klass,
        generate_associations(klass),
        generate_validations(klass),
        generate_methods(klass)
    )
    File.open(file_name, 'w'){ |f| f.write code }

    puts '!!!+++ done +++!!!'
  end

  def generate_associations(klass)
    klass_name      = klass.name
    klass_name_down = klass_name.downcase
    associations = []
    klass.reflect_on_all_associations.each do |assoc|
      associations << "      #{assoc.name}"
    end

    %Q{
  def test_associations
    associations @#{klass_name_down}, %i(
#{associations.join("\n")}
    )
  end
    }
  end

  def generate_validations(klass)
    validations = []
    klass.validators.each do |validator|
      case validator.class.name.to_s
        when 'ActiveRecord::Validations::PresenceValidator'
          validations << validation_presence_of(validator.attributes)
        when 'ActiveModel::Validations::NumericalityValidator'
          validations << validation_numericality_of(
              validator.attributes,
              validator.options
          )
      end
    end
    %Q{
  def test_validations
#{validations.join("\n")}
  end
    }
  end

  def validation_presence_of(attrs)
    out = []
    attrs.each do |attr|
      out << "    assert validate_presence_of(:#{attr})"
    end
    out
  end

  def validation_numericality_of(attrs, options)
    def join_opt(options=nil)
      rules = []
      if options
        options.each do |k, v|
          if k == :allow_nil
            next if v == false
            rules << "      .allow_nil"
          else
            rules << "      .is_#{k}(#{v})"
          end
        end
      end
      rules.join("\n")
    end

    out = []
    attrs.each do |attr|
      out << "    assert validate_numericality_of(:#{attr})" << join_opt(options)
    end
    out
  end

  def generate_methods(klass)
    def skip_method(met)
      %Q{
  def test_#{met}
    skip 'not implemented'
  end
      }
    end

    obj        = klass.new
    klass_name = klass.name
    methods    = []
    obj.public_methods(true).each do |met|
      if obj.method(met).inspect.to_s.include? "#{klass_name}##{met.to_s}>"
        met = met.to_s.gsub('=', '_setter')
        methods << skip_method(met)
      end
    end
    methods.join
  end

  def generate_layout(klass, associations, validations, methods)
    klass_name      = klass.name
    klass_name_down = klass_name.downcase
    klasses_name    = klass_name_down.pluralize
    %Q{require 'test_helper'

class #{klass_name}Test < TestCase
  def setup
    @#{klass_name_down} = #{klasses_name}('#{klasses_name}_001')
  end

  # --- ASSOCIATIONS -------------------------------
#{associations}
  # --- VALIDATIONS --------------------------------
#{validations}
  # --- INSTANCE METHODS ---------------------------
#{methods}
end
    }
  end
end
