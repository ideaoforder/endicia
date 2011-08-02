require 'helper'
require 'base64'

class IntegrationTest < Test::Unit::TestCase
  context 'Calling .get_label with valid options' do
    setup do
      @options = {
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

      @result = Endicia.get_label(@options)
    end
    
    should 'return an Endicia::Label object' do
      assert @result.is_a?(Endicia::Label)
    end
    
    should 'not result in an error message' do
      assert_nil @result.error_message
    end
    
    should 'result in a status of 0 (success)' do
      assert_equal '0', @result.status
    end
    
    should 'produce a shipping label image' do
      sample = File.expand_path('../samples/label.png', File.dirname(__FILE__))
      File.open(sample, 'w') { |f| f.write(Base64.decode64(@result.image)) }
      # Bare minimum assertion to ensure we have *something* there...
      File.open(sample, 'r') { |f| assert f.size > 1024 }
      # ...but mostly we just want to see it with our own eyes:
      puts "\n==============================================================="
      puts " View example shipping label at:\n #{sample} "
      puts "==============================================================="
    end
  end
end
