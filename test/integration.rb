require 'helper'
require 'base64'

class IntegrationTest < Test::Unit::TestCase
  def self.label_request_options
    {
      :Test => "YES",
      :AccountID => "123456",
      :RequesterID => "abc123",
      :PassPhrase => "abc123",
      :PartnerCustomerID => "abc123",
      :PartnerTransactionID => "abc123",
      :MailClass => "First",
      :WeightOz => 1,
      :LabelSize => "4x6",
      :ImageFormat => "PNG",
      :FromCompany => "Acquisitions, Inc.",
      :ReturnAddress1 => "123 Fake Street",
      :FromCity => "Orlando",
      :FromState => "FL",
      :FromPostalCode => "32862",
      :ToAddress1 => "123 Fake Street",
      :ToCity => "San Francisco",
      :ToState => "CA",
      :ToPostalCode => "94102"
    }
  end
  
  def self.should_generate_label_from(description, options)
    should "return an Endicia::Label object given #{description}" do
      result = Endicia.get_label(options)
      assert result.is_a?(Endicia::Label)
    end
    
    should "not result in an error message given #{description}" do
      result = Endicia.get_label(options)
      assert_nil result.error_message
    end
    
    should "result in a status of 0 (success) given #{description}" do
      result = Endicia.get_label(options)
      assert_equal '0', result.status
    end
  end
  
  def self.should_save_sample_label_to(filename, options)
    should "be able to save returned shipping label as #{filename}" do
      result = Endicia.get_label(options)
      sample = File.expand_path("images/#{filename}", File.dirname(__FILE__))
      File.open(sample, 'w') { |f| f.write(Base64.decode64(result.image)) }
      # Bare minimum assertion to ensure we have *something* there...
      File.open(sample, 'r') { |f| assert f.size > 1024 }
      # ...but mostly we just want to see it with our own eyes:
      puts "\n==============================================================="
      puts " Saved example shipping label at:\n #{sample} "
      puts "==============================================================="
    end
  end
  
  context 'calling .get_label' do
    should_generate_label_from("required options", label_request_options)
    should_save_sample_label_to("label.png", label_request_options)
    
    %w(OFF ON UspsOnline Endicia).each do |value|
      options = label_request_options.merge({
        :InsuredMail => value,
        :InsuredValue => "1.00"
      })
      
      should_generate_label_from("options with insurance value of #{value}", options)
      should_save_sample_label_to("sample-insurance-#{value}.png", options)
    end
  end
  
  context 'calling .carrier_pickup_request with valid options' do
    should "be successful" do
      result = Endicia.carrier_pickup_request("abc123", "sd", {
        :AccountID => "123456",
        :PassPhrase => "abc123",
        :Test => "YES"
      })
    
      assert result
      assert result[:success]
    
      assert_not_nil result[:day_of_week]
      assert_not_nil result[:date]
      assert_not_nil result[:confirmation_number]
      assert_not_nil result[:response_body]

      assert_nil result[:error_message]
      assert_nil result[:error_code]
      assert_nil result[:error_description]
    end
  end
end
