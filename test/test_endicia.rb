require 'helper'
require 'base64'

class TestEndicia < Test::Unit::TestCase
  context 'Label' do
    setup do
      # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf
      # Table 3-2: LabelRequestResponse XML Elements
      @response = {
        "Status" => 123,
        "ErrorMessage" => "If there's an error it would be here",
        "Base64LabelImage" => Base64.encode64("the label image"),
        "TrackingNumber" => "abc123",
        "PIC" => "abcd1234",
        "FinalPostage" => 1.2,
        "TransactionID" => 1234,
        "TransactionDateTime" => "20110102030405",
        "CostCenter" => 12345,
        "ReferenceID" => "abcde12345",
        "PostmarkDate" => "20110102",
        "PostageBalance" => 3.4
      }
    end
    
    should "initialize with relevant data from an endicia api response without error" do
      assert_nothing_raised { Endicia::Label.new(@response) }
    end
  end
end
