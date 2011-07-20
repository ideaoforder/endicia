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

  # Return the url for making requests.
  # Pass "YES" to return the url of the test server
  # (this matches the Test attribute/node value for most API calls).
  def self.request_url(test = nil)
    if test && test.upcase == "YES"
      url = "https://www.envmgr.com"
    else
      url = "https://LabelServer.Endicia.com"
    end

    "#{url}/LabelService/EwsLabelService.asmx"
  end

  # Request a shipping label.
  #
  # Accepts a hash of options in the form:
  # { :NodeOrAttributeName => "value", ... }
  #
  # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf Table 3-1
  # for available options.
  #
  # If you are using rails, any applicable options specified in
  # config/endicia.yml will be used as defaults. For example:
  #
  #     development:
  #       Test: YES
  #       AccountID: 123
  #       ...
  #
  # Returns a Endicia::Label object.
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
    
    url = "#{request_url(test_mode)}/GetPostageLabelXML"
    result = self.post(url, :body => body)
    return Endicia::Label.new(result)
  end
  
  # Change your account pass phrase. This is a required step to move to
  # production use after requesting an account.
  #
  # Accepts a hash of options in the form: { :Name => "value", ... }
  #
  # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf Table 5-1
  # for available options.
  #
  # If you are using rails, any applicable options specified in
  # config/endicia.yml will be used as defaults. For example:
  #
  #     development:
  #       Test: YES
  #       AccountID: 123
  #       ...
  #
  # Returns a hash in the form:
  #
  #     { :success => true }
  # 
  # or
  #
  #     { :success => false, :error_message => "the error message" }
  #
  def self.change_pass_phrase(old_phrase, new_phrase, options = {})
    requester_id = options[:RequesterID] || defaults[:RequesterID]
    account_id = options[:AccountID] || defaults[:AccountID]
    test_mode = options[:Test] || defaults[:Test] || "NO"
    
    xml = Builder::XmlMarkup.new
    body = "changePassPhraseRequestXML=" + xml.ChangePassPhraseRequest do |xml|
      xml.NewPassPhrase new_phrase
      xml.RequesterID requester_id
      xml.RequestID "CPP#{Time.now.to_f}"
      xml.CertifiedIntermediary do |xml|
        xml.AccountID account_id
        xml.PassPhrase old_phrase
      end
    end

    url = "#{request_url(test_mode)}/ChangePassPhraseXML"
    result = self.post(url, { :body => body })
    
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

