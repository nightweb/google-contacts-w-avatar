require "net/https"
require "nokogiri"
require "nori"
require "cgi"

module MGContacts
  class Client


    attr_accessor :auth_header
    attr_accessor :gdata_version
    ##
    # Initializes a new client
    # @param [Hash] args
    # @option args [String] :access_token OAuth2 access token
    # @option args [String] :user_email user email, default is default
    # @option args [Symbol] :default_type Which API to call by default, can either be :contacts or :groups, defaults to :contacts
    # @option args [IO, Optional] :debug_output Dump the results of HTTP requests to the given IO
    #
    # @raise [MGContacts::MissingToken]
    #
    # @return [MGContacts::Client]
    def initialize(args)
      unless args[:access_token]
        raise ArgumentError, "Access token must be passed"
      end

      @options = {:default_type => :contacts}.merge(args)
      set_account = args[:user_email] || 'default'
      @api_uri = {
          :contacts => {:all => "https://www.google.com/m8/feeds/contacts/#{set_account}/%s", :create => URI("https://www.google.com/m8/feeds/contacts/#{set_account}/full"), :get => "https://www.google.com/m8/feeds/contacts/#{set_account}/%s/%s", :update => "https://www.google.com/m8/feeds/contacts/#{set_account}/full/%s", :batch => URI("https://www.google.com/m8/feeds/contacts/#{set_account}/full/batch")},
          :groups => {:all => "https://www.google.com/m8/feeds/groups/#{set_account}/%s", :create => URI("https://www.google.com/m8/feeds/groups/#{set_account}/full"), :get => "https://www.google.com/m8/feeds/groups/#{set_account}/%s/%s", :update => "https://www.google.com/m8/feeds/groups/#{set_account}/full/%s", :batch => URI("https://www.google.com/m8/feeds/groups/#{set_account}/full/batch")},
          :photos => {:get => "https://www.google.com/m8/feeds/photos/media/#{set_account}/%s", :update => "https://www.google.com/m8/feeds/photos/media/#{set_account}'/'%s"}
      }
    end

    ##
    # Retrieves all contacts/groups up to the default limit
    # @param [Hash] args
    # @option args [Hash, Optional] :params Query string arguments when sending the API request
    # @option args [Hash, Optional] :headers Any additional headers to pass with the API request
    # @option args [Symbol, Optional] :api_type Override which part of the API is called, can either be :contacts or :groups
    #
    # @raise [Net::HTTPError]
    #
    # @return [MGContacts::List] List containing all the returned entries
    def all(args={})
      uri = api_uri[args.delete(:api_type) || @options[:default_type]]
      raise ArgumentError, "Unsupported type given" unless uri
      response = http_request(:get, URI(uri[:all] % (args.delete(:type) || :full)), args)
      List.new(Nori.parse(response, :nokogiri))
    end

    ##
    # Repeatedly calls {#all} until all data is loaded
    # @param [Hash] args
    # @option args [Hash, Optional] :params Query string arguments when sending the API request
    # @option args [Hash, Optional] :headers Any additional headers to pass with the API request
    # @option args [Symbol, Optional] :api_type Override which part of the API is called, can either be :contacts or :groups
    # @option args [Symbol, Optional] :type What data type to request, can either be :full or :base, defaults to :base
    #
    # @raise [Net::HTTPError]
    #
    # @return [MGContacts::List] List containing all the returned entries
    def paginate_all(args={})
      uri = api_uri[args.delete(:api_type) || @options[:default_type]]
      raise ArgumentError, "Unsupported type given" unless uri
      uri = URI(uri[:all] % (args.delete(:type) || :full))

      while true do
        list = List.new(Nori.parse(http_request(:get, uri, args), :nokogiri))
        list.each {|entry| yield entry}

        # Nothing left to paginate
        # Or just to be safe, we're about to get caught in an infinite loop
        if list.empty? or list.next_uri.nil? or uri == list.next_uri
          break
        end

        uri = list.next_uri

        # If we have any params remove them, the URI Google returns will include them
        args.delete(:params)
      end
    end

    ##
    # Get a single contact or group from the server
    # @param [String] id ID to update
    # @param [Hash] args
    # @option args [Hash, Optional] :params Query string arguments when sending the API request
    # @option args [Hash, Optional] :headers Any additional headers to pass with the API request
    # @option args [Symbol, Optional] :api_type Override which part of the API is called, can either be :contacts or :groups
    # @option args [Symbol, Optional] :type What data type to request, can either be :full or :base, defaults to :base
    #
    # @raise [Net::HTTPError]
    # @raise [MGContacts::InvalidRequest]
    #
    # @return [MGContacts::Element] Single entry found on
    def get(id, args={})
      uri = api_uri[args.delete(:api_type) || @options[:default_type]]
      raise ArgumentError, "Unsupported type given" unless uri

      response = Nori.parse(http_request(:get, URI(uri[:get] % [args.delete(:type) || :full, id]), args), :nokogiri)

      if response and response["entry"]
        Element.new(response["entry"])
      else
        nil
      end
    end

    ##
    # Immediately creates the element on Google
    #
    # @raise [Net::HTTPError]
    # @raise [MGContacts::InvalidRequest]
    # @raise [MGContacts::InvalidResponse]
    # @raise [MGContacts::InvalidKind]
    #
    # @return [MGContacts::Element] Updated element returned from Google
    def create!(element)
      uri = api_uri["#{element.category}s".to_sym]
      raise InvalidKind, "Unsupported kind #{element.category}" unless uri

      xml = "<?xml version='1.0' encoding='UTF-8'?>\n#{element.to_xml}"

      data = Nori.parse(http_request(:post, uri[:create], :body => xml, :headers => {"Content-Type" => "application/atom+xml"}), :nokogiri)
      unless data["entry"]
        raise InvalidResponse, "Created but response wasn't a valid element"
      end

      Element.new(data["entry"])
    end

    ##
    # Immediately updates the element on Google
    # @param [MGContacts::Element] Element to update
    #
    # @raise [Net::HTTPError]
    # @raise [MGContacts::InvalidResponse]
    # @raise [MGContacts::InvalidRequest]
    # @raise [MGContacts::InvalidKind]
    #
    # @return [MGContacts::Element] Updated element returned from Google
    def update!(element)
      uri = api_uri["#{element.category}s".to_sym]
      raise InvalidKind, "Unsupported kind #{element.category}" unless uri

      xml = "<?xml version='1.0' encoding='UTF-8'?>\n#{element.to_xml}"

      data = Nori.parse(http_request(:put, URI(uri[:get] % [:base, File.basename(element.id)]), :body => xml, :headers => {"Content-Type" => "application/atom+xml", "If-Match" => element.etag}), :nokogiri)
      unless data["entry"]
        raise InvalidResponse, "Updated but response wasn't a valid element"
      end

      Element.new(data["entry"])
    end


    ##
    # Immediately updates the element on Google
    # @param [MGContacts::Element] Element to update
    #
    # @raise [Net::HTTPError]
    # @raise [MGContacts::InvalidResponse]
    # @raise [MGContacts::InvalidRequest]
    # @raise [MGContacts::InvalidKind]
    #
    # @return [MGContacts::Element] Updated element returned from Google
    #def upload_photos!(element)
    #  uri = api_uri[:photos]
    #
    #  xml = "<?xml version='1.0' encoding='UTF-8'?>\n#{element.to_xml}"
    #  data = Nori.parse(http_request(:put, URI(uri[:get] % [File.basename(element.id)]), :body => xml, :headers => {"Content-Type" => "application/atom+xml", "If-Match" => element.etag}), :nokogiri)
    #  unless data["entry"]
    #    raise InvalidResponse, "Updated but response wasn't a valid element"
    #  end
    #
    #  Element.new(data["entry"])
    #end

    ##
    # Immediately removes the element on Google
    # @param [MGContacts::Element] Element to delete
    #
    # @raise [Net::HTTPError]
    # @raise [MGContacts::InvalidRequest]
    #
    def delete!(element)
      uri = api_uri["#{element.category}s".to_sym]
      raise InvalidKind, "Unsupported kind #{element.category}" unless uri

      http_request(:delete, URI(uri[:get] % [:base, File.basename(element.id)]), :headers => {"Content-Type" => "application/atom+xml", "If-Match" => element.etag})

      true
    end

    ##
    # Sends an array of {MGContacts::Element} to be updated/created/deleted
    # @param [Array] list Array of elements
    # @param [MGContacts::List] list Array of elements
    # @param [Hash] args
    # @option args [Hash, Optional] :params Query string arguments when sending the API request
    # @option args [Hash, Optional] :headers Any additional headers to pass with the API request
    # @option args [Symbol, Optional] :api_type Override which part of the API is called, can either be :contacts or :groups
    #
    # @raise [Net::HTTPError]
    # @raise [MGContacts::InvalidResponse]
    # @raise [MGContacts::InvalidRequest]
    # @raise [MGContacts::InvalidKind]
    #
    # @return [MGContacts::List] List of elements with the results from the server
    def batch!(list, args={})
      return List.new if list.empty?

      uri = api_uri[args.delete(:api_type) || @options[:default_type]]
      raise ArgumentError, "Unsupported type given" unless uri

      xml = "<?xml version='1.0' encoding='UTF-8'?>\n"
      xml << "<feed xmlns='http://www.w3.org/2005/Atom' xmlns:gContact='http://schemas.google.com/contact/2008' xmlns:gd='http://schemas.google.com/g/2005' xmlns:batch='http://schemas.google.com/gdata/batch'>\n"
      list.each do |element|
        xml << element.to_xml(true) if element.has_modifier?
      end
      xml << "</feed>"

      results = http_request(:post, uri[:batch], :body => xml, :headers => {"Content-Type" => "application/atom+xml"})
      List.new(Nori.parse(results, :nokogiri))
    end

    private
    def build_query_string(params)
      return nil unless params

      query_string = ""

      params.each do |k, v|
        next unless v
        query_string << "&" unless query_string == ""
        query_string << "#{k}=#{CGI::escape(v.to_s)}"
      end

      query_string == "" ? nil : query_string
    end

    def http_request(method, uri, args)
      headers = args[:headers] || {}
      headers["Authorization"] = @auth_header || "Bearer #{@options[:access_token]}"
      headers["GData-Version"] = @gdata_version || "3.0"

      http = Net::HTTP.new(uri.host, uri.port)
      http.set_debug_output(@options[:debug_output]) if @options[:debug_output]
      http.use_ssl = true

      if @options[:verify_ssl]
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      http.start

      query_string = build_query_string(args[:params])
      request_uri = query_string ? "#{uri.request_uri}?#{query_string}" : uri.request_uri

      # GET
      if method == :get
        response = http.request_get(request_uri, headers)
      # POST
      elsif method == :post
        response = http.request_post(request_uri, args.delete(:body), headers)
      # PUT
      elsif method == :put
        response = http.request_put(request_uri, args.delete(:body), headers)
      # DELETE
      elsif method == :delete
        response = http.request(Net::HTTP::Delete.new(request_uri, headers))
      else
        raise ArgumentError, "Invalid method #{method}"
      end

      if response.code == "400" or response.code == "412" or response.code == "404"
        raise InvalidRequest.new("#{response.body} (HTTP #{response.code})")
      elsif response.code == "401"
        raise Unauthorized.new(response.message)
      elsif response.code != "200" and response.code != "201"
        raise Net::HTTPError.new("#{response.message} (#{response.code})", response)
      end

      response.body
    end

    private
      def api_uri
        @api_uri || {}
      end
  end
end
