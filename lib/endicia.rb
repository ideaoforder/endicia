require 'rubygems'
require 'httparty'
require 'active_support/core_ext'
require 'builder'

require 'endicia/label'
require 'endicia/rails_helper'

module Endicia
  include HTTParty
  extend RailsHelper
  
  # We need the following to make requests
  # RequesterID (string): Requester ID (also called Partner ID) uniquely identifies the system making the request. Endicia assigns this ID. The Test Server does not authenticate the RequesterID. Any text value of 1 to 50 characters is valid.
  # AccountID (6 digits): Account ID for the Endicia postage account. The Test Server does not authenticate the AccountID. Any 6-digit value is valid.
  # PassPhrase (string): Pass Phrase for the Endicia postage account. The Test Server does not authenticate the PassPhrase. Any text value of 1 to 64 characters is valid.

  # We probably want the following arguments
  # MailClass, WeightOz, MailpieceShape, Machinable, FromPostalCode
  
  format :xml
  # example XML
  # <LabelRequest><ReturnAddress1>884 Railroad Street, Suite C</ReturnAddress1><ReturnCity>Ypsilanti</ReturnCity><ReturnState>MI</ReturnState><FromPostalCode>48197</FromPostalCode><FromCity>Ypsilanti</FromCity><FromState>MI</FromState><FromCompany>VGKids</FromCompany><ToPostalCode>48197</ToPostalCode><ToAddress1>1237 Elbridge St</ToAddress1><ToCity>Ypsilanti</ToCity><ToState>MI</ToState><PartnerTransactionID>123</PartnerTransactionID><PartnerCustomerID>71212</PartnerCustomerID><MailClass>MediaMail</MailClass><Test>YES</Test><RequesterID>poopants</RequesterID><AccountID>792190</AccountID><PassPhrase>whiplash1</PassPhrase><WeightOz>10</WeightOz></LabelRequest>  

  # Request a shipping label.
  #
  # Accepts a hash of options in the form:
  # { :NodeOrAttributeName => "value", ... }
  #
  # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf Table 3-1
  # for available options.
  #
  # Note: options should be specified in a "flat" hash, they should not be
  # formated to fit the nesting of the XML.
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
    opts[:Test] ||= "NO"
    url = "#{request_url(opts)}/GetPostageLabelXML"

    root_attributes = {
      :LabelType => opts.delete(:LabelType) || "Default",
      :Test => opts.delete(:Test),
      :LabelSize => opts.delete(:LabelSize),
      :ImageFormat => opts.delete(:ImageFormat)
    }
    
    xml = Builder::XmlMarkup.new
    body = "labelRequestXML=" + xml.LabelRequest(root_attributes) do |xm|
      opts.each { |key, value| xm.tag!(key, value) }
    end
    
    result = self.post(url, :body => body)
    return Endicia::Label.new(result)
  end
  
  # Change your account pass phrase. This is a required step to move to
  # production use after requesting an account.
  #
  # Accepts the new phrase and a hash of options in the form:
  #
  #     { :Name => "value", ... }
  #
  # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf Table 5-1
  # for available/required options.
  #
  # Note: options should be specified in a "flat" hash, they should not be
  # formated to fit the nesting of the XML.
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
  #     {
  #       :success => true, # or false
  #       :error_message => "the message", # or nil
  #       :raw_response => <string representation of the HTTParty::Response object>
  #     }
  def self.change_pass_phrase(new_phrase, options = {})
    xml = Builder::XmlMarkup.new
    body = "changePassPhraseRequestXML=" + xml.ChangePassPhraseRequest do |xml|
      authorize_request(xml, options)
      xml.NewPassPhrase new_phrase
      xml.RequestID "CPP#{Time.now.to_f}"
    end

    url = "#{request_url(options)}/ChangePassPhraseXML"
    result = self.post(url, { :body => body })
    parse_result(result, "ChangePassPhraseRequestResponse")
  end

  # Add postage to your account (submit a RecreditRequest). This is a required
  # step to move to production use after requesting an account and changing
  # your pass phrase.
  #
  # Accepts the amount (in dollars) and a hash of options in the form:
  #
  #     { :Name => "value", ... }
  #
  # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf Table 5-1
  # for available/required options.
  #
  # Note: options should be specified in a "flat" hash, they should not be
  # formated to fit the nesting of the XML.
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
  #     {
  #       :success => true, # or false
  #       :error_message => "the message", # or nil
  #       :raw_response => <string representation of the HTTParty::Response object>
  #     }
  def self.buy_postage(amount, options = {})
    xml = Builder::XmlMarkup.new
    body = "recreditRequestXML=" + xml.RecreditRequest do |xml|
      authorize_request(xml, options)
      xml.RecreditAmount amount
      xml.RequestID "BP#{Time.now.to_f}"
    end

    url = "#{request_url(options)}/BuyPostageXML"
    result = self.post(url, { :body => body })
    parse_result(result, "RecreditRequestResponse")
  end
  
  private

  # Given a builder object, add the auth nodes required for many api calls.
  # Will pull values from options hash or defaults if not found.
  def self.authorize_request(xml_builder, options = {})
    requester_id = options[:RequesterID] || defaults[:RequesterID]
    account_id   = options[:AccountID]   || defaults[:AccountID]
    pass_phrase  = options[:PassPhrase]  || defaults[:PassPhrase]
    
    xml_builder.RequesterID requester_id
    xml_builder.CertifiedIntermediary do |xml_builder|
      xml_builder.AccountID account_id
      xml_builder.PassPhrase pass_phrase
    end
  end
  
  # Return the url for making requests.
  # Pass options hash with :Test => "YES" to return the url of the test server
  # (this matches the Test attribute/node value for most API calls).
  def self.request_url(options = {})
    test = (options[:Test] || defaults[:Test] || "NO").upcase == "YES"
    url = test ? "https://www.envmgr.com" : "https://LabelServer.Endicia.com"
    "#{url}/LabelService/EwsLabelService.asmx"
  end

  def self.defaults
    if rails? && @defaults.nil?
      config_file = File.join(rails_root, 'config', 'endicia.yml')
      if File.exist?(config_file)
        @defaults = YAML.load_file(config_file)[rails_env].symbolize_keys
      end
    end
  
    @defaults || {}
  end

  def self.parse_result(result, root)
    parsed_result = {
      :success => false,
      :error_message => nil,
      :raw_response => result.inspect
    }
    
    if result && result[root]
      root = result[root]
      parsed_result[:error_message] = root["ErrorMessage"]
      parsed_result[:success] = root["Status"] && root["Status"].to_s == "0"
    end
    
    parsed_result
  end
end

