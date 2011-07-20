require 'helper'
require 'base64'
require 'ostruct'
require 'nokogiri'

module TestEndiciaHelper
  def expect_label_request_attribute(key, value, returns = {})
    Endicia.expects(:post).with do |request_url, options|
      doc = Nokogiri::XML(options[:body].sub("labelRequestXML=", ""))
      !doc.css("LabelRequest[#{key}='#{value}']").empty?
    end.returns(returns)
  end
  
  def expect_request_url(url)
    Endicia.expects(:post).with do |request_url, options|
      request_url == url
    end.returns({})
  end
  
  def assert_label_request_attributes(key, values)
    values.each do |value|
      expect_label_request_attribute(key, value)
      Endicia.get_label(key.to_sym => value)
    end
  end
  
  def with_rails_endicia_config(attrs)
    Endicia.instance_variable_set(:@defaults, nil)
    
    Endicia.stubs(:rails?).returns(true)
    Endicia.stubs(:rails_root).returns("/project/root")
    Endicia.stubs(:rails_env).returns("development")
    
    config = { "development" => attrs }
    config_path = "/project/root/config/endicia.yml"

    File.stubs(:exist?).with(config_path).returns(true)
    YAML.stubs(:load_file).with(config_path).returns(config)
    
    yield
    
    Endicia.instance_variable_set(:@defaults, nil)
  end
  
  def the_production_server_url(req_path)
    "https://LabelServer.Endicia.com/LabelService/EwsLabelService.asmx/#{req_path}"
  end
  
  # Don't call this "test_server_url" or ruby will try to run it as a test.
  def the_test_server_url(req_path)
    "https://www.envmgr.com/LabelService/EwsLabelService.asmx/#{req_path}"
  end  
end

class TestEndicia < Test::Unit::TestCase
  include TestEndiciaHelper
  
  context '.get_label' do
    should "use test server url if :Test option is YES" do
      expect_request_url(the_test_server_url("GetPostageLabelXML"))
      Endicia.get_label(:Test => "YES")
    end
  
    should "use production server url if :Test option is NO" do
      expect_request_url(the_production_server_url("GetPostageLabelXML"))
      Endicia.get_label(:Test => "NO")
    end
  
    should "use production server url if passed no :Test option" do
      expect_request_url(the_production_server_url("GetPostageLabelXML"))
      Endicia.get_label
    end
  end
  
  context 'root node attributes on .get_label request' do
    setup do
      @request_url = "http://test.com"
      Endicia.stubs(:request_url).returns(@request_url)
    end
  
    should "pass LabelType option" do
      assert_label_request_attributes("LabelType", %w(Express CertifiedMail Priority))
    end
  
    should "set LabelType attribute to Default by default" do
      expect_label_request_attribute("LabelType", "Default")
      Endicia.get_label
    end
  
    should "pass Test option" do
      assert_label_request_attributes("Test", %w(YES NO))
    end
  
    should "pass LabelSize option" do
      assert_label_request_attributes("LabelSize", %w(4x6 6x4 7x3))
    end
  
    should "pass ImageFormat option" do
      assert_label_request_attributes("ImageFormat", %w(PNG GIFT PDF))
    end
  end
  
  context 'Label' do
    setup do
      # See https://app.sgizmo.com/users/4508/Endicia_Label_Server.pdf
      # Table 3-2: LabelRequestResponse XML Elements
      @response = { "LabelRequestResponse" => {
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
      }}
    end
  
    should "initialize with relevant data from an endicia api response without error" do
      assert_nothing_raised { Endicia::Label.new(@response) }
    end
    
    should "include raw response" do
      @response.stubs(:inspect).returns("the raw response")
      the_label = Endicia::Label.new(@response)
      assert_equal "the raw response", the_label.raw_response
    end
  end
  
  context 'defaults in rails' do
    should "load from config/endicia.yml" do
      attrs = {
        :AccountID   => 123,
        :RequesterID => "abc",
        :PassPhrase  => "123",
      }
    
      with_rails_endicia_config(attrs) do
        assert_equal attrs, Endicia.defaults
      end
    end
  
    should "support root node request attributes" do
      attrs = {
        :Test        => "YES",
        :LabelType   => "Priority",
        :LabelSize   => "6x4",
        :ImageFormat => "PNG"
      }
    
      with_rails_endicia_config(attrs) do
        attrs.each do |key, value|
          expect_label_request_attribute(key, value)
          Endicia.get_label
        end
      end
    end
  end
  
  context '.change_pass_phrase(new, options)' do
    should 'make a ChangePassPhraseRequest call to the Endicia API' do
      Endicia.stubs(:request_url).returns("http://example.com/api")
      Time.any_instance.stubs(:to_f).returns("timestamp")
      
      Endicia.expects(:post).with do |request_url, options|
        request_url == "http://example.com/api/ChangePassPhraseXML" &&
        options[:body] &&
        options[:body].match(/changePassPhraseRequestXML=(.+)/) do |match|
          doc = Nokogiri::Slop(match[1])
          doc.ChangePassPhraseRequest &&
          doc.ChangePassPhraseRequest.RequesterID.content == "abcd" &&
          doc.ChangePassPhraseRequest.RequestID.content == "CPPtimestamp" &&
          doc.ChangePassPhraseRequest.CertifiedIntermediary.AccountID.content == "123456" &&
          doc.ChangePassPhraseRequest.CertifiedIntermediary.PassPhrase.content == "oldPassPhrase" &&
          doc.ChangePassPhraseRequest.NewPassPhrase.content == "newPassPhrase"
        end
      end
      
      Endicia.change_pass_phrase("newPassPhrase", {
        :PassPhrase => "oldPassPhrase",
        :RequesterID => "abcd",
        :AccountID => "123456"
      })
    end
    
    should 'use credentials from rails endicia config if present' do
      attrs = {
        :PassPhrase => "old_phrase",
        :RequesterID => "efgh",
        :AccountID => "456789"
      }
      with_rails_endicia_config(attrs) do
        Endicia.expects(:post).with do |request_url, options|
          options[:body] &&
          options[:body].match(/changePassPhraseRequestXML=(.+)/) do |match|
            doc = Nokogiri::Slop(match[1])
            doc.ChangePassPhraseRequest &&
            doc.ChangePassPhraseRequest.RequesterID.content == "efgh" &&
            doc.ChangePassPhraseRequest.CertifiedIntermediary.AccountID.content == "456789" &&
            doc.ChangePassPhraseRequest.CertifiedIntermediary.PassPhrase.content == "old_phrase"
          end
        end
        
        Endicia.change_pass_phrase("new")
      end
    end
    
    should 'use test url if passed :Test => YES option' do
      expect_request_url(the_test_server_url("ChangePassPhraseXML"))
      Endicia.change_pass_phrase("new", { :Test => "YES" })
    end
    
    should 'use production url if not passed :Test => YES option' do
      expect_request_url(the_production_server_url("ChangePassPhraseXML"))
      Endicia.change_pass_phrase("new")
    end
      
    should 'use test option from rails endicia config if present' do
      attrs = { :Test => "YES" }
      with_rails_endicia_config(attrs) do
        expect_request_url(the_test_server_url("ChangePassPhraseXML"))
        Endicia.change_pass_phrase("new")
      end
    end
    
    should "include raw in return hash" do
      response = stub_everything("response", :inspect => "the raw response")
      Endicia.stubs(:post).returns(response)
      result = Endicia.change_pass_phrase("new")
      assert_equal "the raw response", result[:raw_response]
    end    
    
    context 'when successful' do
      setup do
        Endicia.stubs(:post).returns({
          "ChangePassPhraseRequestResponse" => { "Status" => "0" }
        })
      end
      
      should 'return hash with :success => true' do
        result = Endicia.change_pass_phrase("new_phrase")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end
    end
    
    context 'when not successful' do
      setup do
        Endicia.stubs(:post).returns({
          "ChangePassPhraseRequestResponse" => {
            "Status" => "1", "ErrorMessage" => "the error message" }
        })
      end
  
      should 'return hash with :success => false' do
        result = Endicia.change_pass_phrase("new_phrase")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'return hash with an :error_message' do
        result = Endicia.change_pass_phrase("new_phrase")
        assert_equal "the error message", result[:error_message]
      end
    end
  end

  context '.buy_postage(amount)' do
    should 'make a BuyPostage call to the Endicia API' do
      Endicia.stubs(:request_url).returns("http://example.com/api")
      Time.any_instance.stubs(:to_f).returns("timestamp")
      
      Endicia.expects(:post).with do |request_url, options|
        request_url == "http://example.com/api/BuyPostageXML" &&
        options[:body] &&
        options[:body].match(/recreditRequestXML=(.+)/) do |match|
          doc = Nokogiri::Slop(match[1])
          doc.RecreditRequest &&
          doc.RecreditRequest.RequesterID.content == "abcd" &&
          doc.RecreditRequest.RequestID.content == "BPtimestamp" &&
          doc.RecreditRequest.CertifiedIntermediary.AccountID.content == "123456" &&
          doc.RecreditRequest.CertifiedIntermediary.PassPhrase.content == "PassPhrase" &&
          doc.RecreditRequest.RecreditAmount.content == "125.99"
        end
      end
      
      Endicia.buy_postage("125.99", {
        :PassPhrase => "PassPhrase",
        :RequesterID => "abcd",
        :AccountID => "123456"
      })
    end
    
    should 'use credentials from rails endicia config if present' do
      attrs = {
        :PassPhrase => "my_phrase",
        :RequesterID => "efgh",
        :AccountID => "456789"
      }
      with_rails_endicia_config(attrs) do
        Endicia.expects(:post).with do |request_url, options|
          options[:body] &&
          options[:body].match(/recreditRequestXML=(.+)/) do |match|
            doc = Nokogiri::Slop(match[1])
            doc.RecreditRequest &&
            doc.RecreditRequest.RequesterID.content == "efgh" &&
            doc.RecreditRequest.CertifiedIntermediary.AccountID.content == "456789" &&
            doc.RecreditRequest.CertifiedIntermediary.PassPhrase.content == "my_phrase"
          end
        end
        
        Endicia.buy_postage("100")
      end
    end
    
    should 'use test url if passed :Test => YES option' do
      expect_request_url(the_test_server_url("BuyPostageXML"))
      Endicia.buy_postage("100", { :Test => "YES" })
    end
    
    should 'use production url if not passed :Test => YES option' do
      expect_request_url(the_production_server_url("BuyPostageXML"))
      Endicia.buy_postage("100")
    end
      
    should 'use test option from rails endicia config if present' do
      attrs = { :Test => "YES" }
      with_rails_endicia_config(attrs) do
        expect_request_url(the_test_server_url("BuyPostageXML"))
        Endicia.buy_postage("100")
      end
    end
    
    should "include raw in return hash" do
      response = stub_everything("response", :inspect => "the raw response")
      Endicia.stubs(:post).returns(response)
      result = Endicia.buy_postage("100")
      assert_equal "the raw response", result[:raw_response]
    end
    
    context 'when successful' do
      setup do
        Endicia.stubs(:post).returns({
          "RecreditRequestResponse" => { "Status" => "0" }
        })
      end
      
      should 'return hash with :success => true' do
        result = Endicia.buy_postage("100")
        assert result[:success], "result[:success] should be true but it's #{result[:success].inspect}"
      end
    end
    
    context 'when not successful' do
      setup do
        Endicia.stubs(:post).returns({
          "RecreditRequestResponse" => {
            "Status" => "1", "ErrorMessage" => "the error message" }
        })
      end
  
      should 'return hash with :success => false' do
        result = Endicia.buy_postage("100")
        assert !result[:success], "result[:success] should be false but it's #{result[:success].inspect}"
      end
      
      should 'return hash with an :error_message' do
        result = Endicia.buy_postage("100")
        assert_equal "the error message", result[:error_message]
      end
    end
  end
end
