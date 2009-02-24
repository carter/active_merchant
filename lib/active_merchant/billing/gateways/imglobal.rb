require 'base64'
require 'rubygems'
gem 'builder'
require 'rexml/document'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class ImglobalGateway < Gateway
      TEST_URL = 'https://c3-test.wirecard.com/secure/ssl-gateway'
      LIVE_URL = 'https://c3.wirecard.com/secure/ssl-gateway'
      
      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']
      
      # Default Currency
      self.default_currency = 'USD'
      self.money_format = :cents
      
      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      
      # The homepage URL of the gateway
      self.homepage_url = 'http://www.imglobalpayments.com/'
      
      # The name of the gateway
      self.display_name = 'ImGlobal Payments'
      
      def initialize(options = {})
        requires!(options, :login, :password, :location, :business_case_signature)
        @options = options
        super
      end  
      
      def authorize(money, creditcard, options = {})
        post = {}
        add_invoice(post, options)
        add_creditcard(post, creditcard)        
        add_address(post, creditcard, options)        
        add_customer_data(post, options)
        
        commit('authonly', money, post)
      end
      
      
      
      
      
      def purchase(money, creditcard, options = {})
        xm = Builder::XmlMarkup.new(:indent => 2)
        xm.CC_TRANSACTION(:mode => (test? ? 'demo' : 'live')) do
          xm.TransactionID(options[:order_id])
          xm.SalesDate(Date.today)
          xm.CommerceType('eCommerce')
          xm.Amount(amount(money), :minorunits => '2')
          xm.Currency(options[:currency] || currency(money))
          xm.CountryCode(@options[:location])
          xm.Usage(options[:description])
          xm.RECURRING_TRANSATION do
            xm.Type('Initial')
          end
          xm.CREDIT_CARD_DATA do
            xm.CreditCardNumber(creditcard.number)
            xm.CVC2(sprintf("%03d", creditcard.verification_value))
            xm.ExpirationYear(creditcard.year)

            # must have leading 0
            if creditcard.month.to_s.length == 1
              month = '0' + creditcard.month.to_s
            else
              month = creditcard.month.to_s
            end

            xm.ExpirationMonth(month)
            xm.CardHolderName(creditcard.name)
          end
          xm.CONTACT_DATA do
            xm.IPAddress(options[:ip])
          end
          xm.CORPTRUSTCENTER_DATA do
            xm.ADDRESS do
              address = options[:billing_address] || options[:shipping_address] || options[:address]
              xm.FirstName(creditcard.first_name)
              xm.LastName(creditcard.last_name)
              xm.Address1(address[:address1])
              xm.Address2(address[:address2]) unless address[:address2].blank?
              xm.City(address[:city])
              xm.State(address[:state]) unless address[:state].blank?
              xm.Country(address[:country])
              xm.Phone(address[:phone]) unless address[:phone].blank?
            end
          end
        end  
        commit(build_request('PURCHASE', xm.target!))
      end                       
    
      def capture(money, authorization, options = {})
        commit('capture', money, post)
      end
    
      private                       
      
      def parse(body)
        xml = REXML::Document.new(body)
        xml.elements.to_a('WIRECARD_BXML/W_REPONSE/W_JOB/*/CC_TRANSACTION/PROCESSING_STATUS')
      end     
      
      def commit(request)
        url = test? ? TEST_URL : LIVE_URL
         response = ssl_post(url, request, {'Content-Type' => 'text/xml', 'Authorization' => 'Basic '+token(@options[:login], @options[:password])})
        Response.new(success?(response), message_from(response), {:request => request,
        :response => response, :username => @options[:login], :password => @options[:password], :url => url},{ 
          :test => test?, 
          :authorization => authorization_from(response)}
        )
      end
      
      def build_request(action, body)
        xm = Builder::XmlMarkup.new(:indent => 2)
        xm.instruct!
        xm.WIRECARD_BXML('xmlns:xsi' => 'http://www.w3.org/1999/XMLSchema-instance') do
          xm.W_REQUEST do
            xm.W_JOB do
              xm.JobID
              xm.BusinessCaseSignature(@options[:business_case_signature])
              xm.tag!('FNC_CC_'+action.upcase) do
                xm.FunctionID
                xm << body
              end
            end
          end
        end
        xm.target!
      end
      
      def token(username, password)
        Base64.encode64(username+':'+password).strip
      end
      
      def success?(response)
        xml = REXML::Document.new(response)
        xml_search = xml.elements['WIRECARD_BXML/W_RESPONSE/W_JOB/*/CC_TRANSACTION/PROCESSING_STATUS/FunctionResult']
        response_code = xml_search.text if xml_search
        if response_code == 'ACK' || response_code == 'PENDING'
          return true
        else
          return false
        end
      end
      
      def test?
        ActiveMerchant::Billing::Base.mode == :test
      end
      
      def authorization_from(response)
        xml = REXML::Document.new(response)
        xml_search = xml.elements['WIRECARD_BXML/W_RESPONSE/W_JOB/*/CC_TRANSACTION/PROCESSING_STATUS/AuthorizationCode']
        authorization_code = xml_search.text if xml_search
      end
      
      def message_from(response)
        return 'Could not login to ImGlobal' if response =~ /This.is.an.error.page/
        xml = REXML::Document.new(response)
        xml_search = xml.elements['WIRECARD_BXML/W_RESPONSE/W_JOB/*/CC_TRANSACTION/PROCESSING_STATUS/ERROR/Message']
        if xml_search
          return xml_search.text
        else
          xml_search = xml.elements['WIRECARD_BXML/W_RESPONSE/W_JOB/*/CC_TRANSACTION/PROCESSING_STATUS/Info']
          return xml_search.text if xml_search
        end
      end
    end
  end
end
