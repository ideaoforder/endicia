require 'rubygems'
require 'httparty'

module Endicia
  include HTTParty
  
  # We need the following to make requests
  # RequesterID (string): Requester ID (also called Partner ID) uniquely identifies the system making the request. Endicia assigns this ID. The Test Server does not authenticate the RequesterID. Any text value of 1 to 50 characters is valid.
  # AccountID (6 digits): Account ID for the Endicia postage account. The Test Server does not authenticate the AccountID. Any 6-digit value is valid.
  # PassPhrase (string): Pass Phrase for the Endicia postage account. The Test Server does not authenticate the PassPhrase. Any text value of 1 to 64 characters is valid.

  # if we're in a Rails env, let's load the config file
  if defined? Rails.root
    rails_root = Rails.root.to_s 
  elsif defined? RAILS_ROOT
    rails_root = RAILS_ROOT 
  end
  @defaults = YAML.load_file(File.join(rails_root, 'config', 'endicia.yml'))[Rails.env].symbolize_keys if defined? rails_root and File.exist? "#{rails_root}/config/endicia.yml" 
  @defaults = Hash.new if @defaults.nil?

  # We probably want the following arguments
  # MailClass, WeightOz, MailpieceShape, Machinable, FromPostalCode
  
  format :xml
  # example XML
  # <LabelRequest><ReturnAddress1>884 Railroad Street, Suite C</ReturnAddress1><ReturnCity>Ypsilanti</ReturnCity><ReturnState>MI</ReturnState><FromPostalCode>48197</FromPostalCode><FromCity>Ypsilanti</FromCity><FromState>MI</FromState><FromCompany>VGKids</FromCompany><ToPostalCode>48197</ToPostalCode><ToAddress1>1237 Elbridge St</ToAddress1><ToCity>Ypsilanti</ToCity><ToState>MI</ToState><PartnerTransactionID>123</PartnerTransactionID><PartnerCustomerID>71212</PartnerCustomerID><MailClass>MediaMail</MailClass><Test>YES</Test><RequesterID>poopants</RequesterID><AccountID>792190</AccountID><PassPhrase>whiplash1</PassPhrase><WeightOz>10</WeightOz></LabelRequest>  

  def self.get_label(opts={})
    body = "labelRequestXML=" + @defaults.merge(opts).to_xml(:skip_instruct => true, :skip_types => true, :root => 'LabelRequest', :indent => 0)
    result = self.post("https://www.envmgr.com/LabelService/EwsLabelService.asmx/GetPostageLabelXML", :body => body)
    return Endicia::Label.new(result["LabelRequestResponse"])
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
                  :cost_center,
                  :error_message
    def initialize(data)
      data.each do |k, v|
        k = "image" if k == 'Base64LabelImage'
        send(:"#{k.tableize.singularize}=", v) if !k['xmlns'] and self.respond_to? k.tableize.singularize
      end
    end
  end
end
