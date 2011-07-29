module Endicia
  module RailsHelper
    private
    
    def rails?
      defined?(Rails) || defined?(RAILS_ROOT)
    end

    def rails_root
      if rails?
        defined?(Rails.root) ? Rails.root : RAILS_ROOT
      end
    end

    def rails_env
      if rails?
        defined?(Rails.env) ? Rails.env : ENV['RAILS_ENV']
      end
    end
  end
end
