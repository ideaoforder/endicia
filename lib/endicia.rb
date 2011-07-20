require 'rubygems'
require 'httparty'
require 'active_support/core_ext'
require 'builder'

module Endicia
  include HTTParty
  
  # We need the following to make requests
  # RequesterID (string): Requester ID (also called Partner ID) uniquely identifies the system making the request. Endicia assigns this ID. The Test Server does not authenticate the RequesterID. Any text value of 1 to 50 characters is valid.
  # AccountID (6 digits): Account ID for the Endicia postage account. The Test Server does not authenticate the AccountID. Any 6-digit value is valid.
  # PassPhrase (string): Pass Phrase for the Endicia postage account. The Test Server does not authenticate the PassPhrase. Any text value of 1 to 64 characters is valid.

  def self.defaults
    if rails? && @defaults.nil?
      config_file = File.join(rails_root, 'config', 'endicia.yml')
      if File.exist?(config_file)
        @defaults = YAML.load_file(config_file)[rails_env].symbolize_keys
      end
    end
  
    @defaults || {}
  end
  
  # We probably want the following arguments
  # MailClass, WeightOz, MailpieceShape, Machinable, FromPostalCode
  
  format :xml
  # example XML
  # <LabelRequest><ReturnAddress1>884 Railroad Street, Suite C</ReturnAddress1><ReturnCity>Ypsilanti</ReturnCity><ReturnState>MI</ReturnState><FromPostalCode>48197</FromPostalCode><FromCity>Ypsilanti</FromCity><FromState>MI</FromState><FromCompany>VGKids</FromCompany><ToPostalCode>48197</ToPostalCode><ToAddress1>1237 Elbridge St</ToAddress1><ToCity>Ypsilanti</ToCity><ToState>MI</ToState><PartnerTransactionID>123</PartnerTransactionID><PartnerCustomerID>71212</PartnerCustomerID><MailClass>MediaMail</MailClass><Test>YES</Test><RequesterID>poopants</RequesterID><AccountID>792190</AccountID><PassPhrase>whiplash1</PassPhrase><WeightOz>10</WeightOz></LabelRequest>  

  def self.request_url(test = nil)
    if test && test.upcase == "YES"
      "https://www.envmgr.com/LabelService/EwsLabelService.asmx/GetPostageLabelXML"
    else
      # TODO: handle production urls
      "the production url"
    end
  end

  def self.get_label(opts={})
    opts = defaults.merge(opts)
    test_mode = opts.delete(:Test) || "NO"
    root_attributes = {
      :LabelType => opts.delete(:LabelType) || "Default",
      :Test => test_mode,
      :LabelSize => opts.delete(:LabelSize),
      :ImageFormat => opts.delete(:ImageFormat)
    }
    
    xml = Builder::XmlMarkup.new
    body = "labelRequestXML=" + xml.LabelRequest(root_attributes) do |xm|
      opts.each { |key, value| xm.tag!(key, value) }
    end
    
    result = self.post(request_url(test_mode), :body => body)
    return Endicia::Label.new(result)
  end
  
  def self.change_pass_phrase(old_phrase, new_phrase, options = {})
    requester_id = options[:RequesterID] || defaults[:RequesterID]
    account_id = options[:AccountID] || defaults[:AccountID]
    test_mode = options[:Test] || defaults[:Test] || "NO"
    
    xml = Builder::XmlMarkup.new
    result = self.post(request_url(test_mode), { :body => "changePassPhraseRequestXML=" +
      xml.ChangePassPhraseRequest do |xml|
        xml.NewPassPhrase new_phrase
        xml.RequesterID requester_id
        xml.RequestID "CPP#{Time.now.to_f}"
        xml.CertifiedIntermediary do |xml|
          xml.AccountID account_id
          xml.PassPhrase old_phrase
        end
      end
    })
    
    success = false
    error_message = nil
    
    if result && result["ChangePassPhraseRequestResponse"]
      error_message = result["ChangePassPhraseRequestResponse"]["ErrorMessage"]
      success = result["ChangePassPhraseRequestResponse"]["Status"] &&
                result["ChangePassPhraseRequestResponse"]["Status"].to_s == "0"
    end
    
    { :success => success, :error_message => error_message }
  end
  
  class Label
    attr_accessor :image, 
                  :status, 
                  :tracking_number, 
                  :final_postage, 
                  :transaction_date_time, 
                  :transaction_id, 
                  :postmark_date, 
                  :postage_balance, 
                  :pic,
                  :error_message,
                  :reference_id,
                  :cost_center,
                  :raw_response
    def initialize(result)
      self.raw_response = result.inspect
      data = result["LabelRequestResponse"] || {}
      data.each do |k, v|
        k = "image" if k == 'Base64LabelImage'
        send(:"#{k.tableize.singularize}=", v) if !k['xmlns']
      end
    end
  end
  
  private
  
  def self.rails?
    defined?(Rails) || defined?(RAILS_ROOT)
  end
  
  def self.rails_root
    if rails?
      defined?(Rails.root) ? Rails.root : RAILS_ROOT
    end
  end
  
  def self.rails_env
    if rails?
      defined?(Rails.env) ? Rails.env : ENV['RAILS_ENV']
    end
  end
end

