module Statistics
  def self.included(base)
    base.extend(HasStats)
  end

  # This extension provides the ability to 
  module HasStats

    
    SUPPORTED_CALCULATIONS = [:average, :count, :maximum, :minimum, :sum]
    
    # OPTIONS:
    #
    #* +average+, +count+, +sum+, +maximum+, +minimum+ - Only one of these keys is passed, which 
    #   one depends on the type of operation. The value is an array of named scopes to scope the 
    #   operation by (+:all+ should be used if no scopes are to be applied)
    #* +column_name+ - The SQL column to perform the operation on (default: +id+)
    #* +filter_on+ - A hash with keys that represent filters. The with values in the has are rules 
    #   on how to generate the query for the correspond filter.
    #
    #   Additional options can also be passed in that would normally be passed to an ActiveRecord 
    #   +calculate+ call, like +conditions+, +joins+, etc
    #
    # EXAMPLE:
    #
    #  class MockModel < ActiveRecord::Base
    #    
    #    named_scope :my_scope, :conditions => 'value > 5'
    #     
    #    define_statistic "Basic Count", :count => :all
    #    define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    #    define_statistic "Chained Scope Count", :count => [:all, :my_scope]
    #    define_statistic "Default Filter", :count => :all
    #    define_statistic "Custom Filter", :count => :all, :filter_on => { :channel => 'channel = ?', :start_date => 'DATE(created_at) > ?' }
    #  end
    def define_statistic(name, options)
      method_name = name.gsub(" ", "").underscore + "_stat"
      
      @statistics ||= {}
      @filter_all_on ||= {}
      @statistics[name] = method_name
      
      options = { :column_name => :id }.merge(options)

      calculation = options.keys.find {|opt| SUPPORTED_CALCULATIONS.include?(opt)}
      calculation ||= :count
      
      # We must use the metaclass here to metaprogrammatically define a class method
      (class<<self; self; end).instance_eval do 
        define_method(method_name) do |filters|
          scoped_options = options.dclone
          filters.each do |key, value|
            if value
              sql = (@filter_all_on.merge(scoped_options[:filter_on] || {}))[key].gsub("?", "'#{value}'")
              sql_frag = ActiveRecord::Base.send(:sanitize_sql_for_conditions, sql)
              case 
                when sql_frag.nil? : nil
                when scoped_options[:conditions].nil? : scoped_options[:conditions] = sql_frag
                when scoped_options[:conditions].is_a?(Array) : scoped_options[:conditions][0].concat(" AND #{sql_frag}")
                when scoped_options[:conditions].is_a?(String) : scoped_options[:conditions].concat(" AND #{sql_frag}")
              end
            end
          end if filters.is_a?(Hash)
          
          base = self
          # chain named scopes
          scopes = Array(scoped_options[calculation])
          scopes.each do |scope|
            base = base.send(scope)
          end if scopes != [:all] 
          base.calculate(calculation, scoped_options[:column_name], sql_options(scoped_options))
        end
      end
    end
    
    # Defines a statistic using a block that has access to all other defined statistics
    # 
    # EXAMPLE:
    # class MockModel < ActiveRecord::Base
    #   define_statistic "Basic Count", :count => :all
    #   define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    #   define_calculated_statistic "Total Profit"
    #     defined_stats('Basic Sum') * defined_stats('Basic Count')
    #   end
    def define_calculated_statistic(name, &block)
      method_name = name.gsub(" ", "").underscore + "_stat"

      @statistics ||= {}
      @statistics[name] = method_name
      
      (class<<self; self; end).instance_eval do 
        define_method(method_name) do |filters|
          @filters = filters
          yield
        end
      end
    end
    
    # returns an array containing the names/keys of all defined statistics
    def statistics_keys
      @statistics.keys
    end
    
    # Calculates all the statistics defined for this AR class and returns a hash with the values.
    # There is an optional parameter that is a hash of all values you want to filter by.
    #
    # EXAMPLE:
    # MockModel.statistics
    # MockModel.statistics(:user_type => 'registered', :user_status => 'active')
    def statistics(filters = {}, except = nil)
      (@statistics || {}).inject({}) do |stats_hash, stat|
        stats_hash[stat.first] = send(stat.last, filters) if stat.last != except
        stats_hash
      end
    end
    
    # returns a single statistic based on the +stat_name+ paramater passed in and
    # similarly to the +statistics+ method, it also can take filters.
    #
    # EXAMPLE:
    # MockModel.get_stat('Basic Count')
    # MockModel.get_stat('Basic Count', :user_type => 'registered', :user_status => 'active')
    def get_stat(stat_name, filters = {})
      send(@statistics[stat_name], filters) if @statistics[stat_name]
    end
    
    # to keep things DRY anything that all statistics need to be filterable by can be defined
    # seperatly using this method
    #
    # EXAMPLE:
    #
    # class MockModel < ActiveRecord::Base
    #   define_statistic "Basic Count", :count => :all
    #   define_statistic "Basic Sum", :sum => :all, :column_name => 'amount'
    #
    #   filter_all_stats_on(:user_id, "user_id = ?")
    # end
    def filter_all_stats_on(name, cond)
      @filter_all_on ||= {}
      @filter_all_on[name] = cond
    end
    
    private

    def defined_stats(name)
      get_stat(name, @filters)
    end

    def sql_options(options)
      SUPPORTED_CALCULATIONS.each do |deletable|
        options.delete(deletable)
      end
      options.delete(:column_name)
      options.delete(:filter_on)
      options
    end
  end
    
end