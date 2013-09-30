require "net/https"
require "nokogiri"
require "nori"
require "cgi"

module GoogleContacts
  class Client


    attr_accessor :auth_header
    attr_accessor :gdata_version
    attr_accessor :client
    attr_accessor :reconnect
    attr_accessor :raise_not_found
    ##
    # Initializes a new client
    # @param [Hash] args
    # @option args [String] :access_token OAuth2 access token
    # @option args [String] :user_email user email, default is default
    # @option args [Symbol] :default_type Which API to call by default, can either be :contacts or :groups, defaults to :contacts
    # @option args [IO, Optional] :debug_output Dump the results of HTTP requests to the given IO
    #
    # @raise [GoogleContacts::MissingToken]
    #
    # @return [GoogleContacts::Client]
    def initialize(args)
      unless args[:access_token]
        raise ArgumentError, "Access token must be passed"
      end
      @reconnect = args[:reconnect]
      @client = args[:client]
      @auth_header = args[:auth_header]
      @gdata_version = args[:gdata_version]
      @options = {:default_type => :contacts}.merge(args)
      set_account = args[:user_email] || 'default'
      @api_uri = {
          :contacts => {:all => "https://www.google.com/m8/feeds/contacts/#{set_account}/%s", :create => URI("https://www.google.com/m8/feeds/contacts/#{set_account}/full"), :get => "https://www.google.com/m8/feeds/contacts/#{set_account}/%s/%s", :update => "https://www.google.com/m8/feeds/contacts/#{set_account}/full/%s", :batch => URI("https://www.google.com/m8/feeds/contacts/#{set_account}/full/batch")},
          :groups => {:all => "https://www.google.com/m8/feeds/groups/#{set_account}/%s", :create => URI("https://www.google.com/m8/feeds/groups/#{set_account}/full"), :get => "https://www.google.com/m8/feeds/groups/#{set_account}/%s/%s", :update => "https://www.google.com/m8/feeds/groups/#{set_account}/self/%s", :batch => URI("https://www.google.com/m8/feeds/groups/#{set_account}/full/batch")},
      }
      @raise_not_found = false
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
    # @return [GoogleContacts::List] List containing all the returned entries
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
    # @return [GoogleContacts::List] List containing all the returned entries
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
    # @raise [GoogleContacts::InvalidRequest]
    #
    # @return [GoogleContacts::Element] Single entry found on
    def get(id, args={})
      uri = api_uri[args.delete(:api_type) || @options[:default_type]]
      raise ArgumentError, "Unsupported type given" unless uri
      begin
        xml_text = http_request(:get, URI(uri[:get] % [args.delete(:type) || :full, id]), args)
        response = Nori.parse(xml_text, :nokogiri)
      rescue RecordNotFound
        raise RecordNotFound unless @raise_not_found === false
      end

      if response and response["entry"]
        el = Element.new(response["entry"])
        el.xml_text = xml_text
        el.xml_response = response
        el.photo_file_name = get_photo(el, File.basename(el.id))
        el
      else
        nil
      end
    end



    ##
    # Immediately creates the element on Google
    #
    # @raise [Net::HTTPError]
    # @raise [GoogleContacts::InvalidRequest]
    # @raise [GoogleContacts::InvalidResponse]
    # @raise [GoogleContacts::InvalidKind]
    #
    # @return [GoogleContacts::Element] Updated element returned from Google

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
    # @param [GoogleContacts::Element] Element to update
    #
    # @raise [Net::HTTPError]
    # @raise [GoogleContacts::InvalidResponse]
    # @raise [GoogleContacts::InvalidRequest]
    # @raise [GoogleContacts::InvalidKind]
    #
    # @return [GoogleContacts::Element] Updated element returned from Google
    def update!(element)
      uri = api_uri["#{element.category}s".to_sym]
      raise InvalidKind, "Unsupported kind #{element.category}" unless uri

      xml = "<?xml version='1.0' encoding='UTF-8'?>\n#{element.to_xml}"

      begin
        data = Nori.parse(http_request(:put, URI(uri[:get] % [:base, File.basename(element.id)]), :body => xml, :headers => {"Content-Type" => "application/atom+xml", "If-Match" => element.etag}), :nokogiri)
        unless data["entry"]
          raise InvalidResponse, "Updated but response wasn't a valid element"
        end
        el = Element.new(data["entry"])
        if el.photo_send_delete_request
          http_request(:put, URI(uri[:get] % [:base, File.basename(element.id)]), :body => nil, :headers => {"Content-Type" => "application/atom+xml", "If-Match" => element.etag})
        end
        #update_photo!(el)
        el
      rescue RecordNotFound
        raise RecordNotFound unless @raise_not_found === false
        nil
      end
    end


    ##
    # Immediately removes the element on Google
    # @param [GoogleContacts::Element] Element to delete
    #
    # @raise [Net::HTTPError]
    # @raise [GoogleContacts::InvalidRequest]
    #
    def delete!(element)
      uri = api_uri["#{element.category}s".to_sym]
      raise InvalidKind, "Unsupported kind #{element.category}" unless uri
      begin
      http_request(:delete, URI(uri[:get] % [:base, File.basename(element.id)]), :headers => {"Content-Type" => "application/atom+xml", "If-Match" => element.etag})
      rescue RecordNotFound
        raise RecordNotFound unless @raise_not_found === false
        nil
      end

    end

    ##
    # Sends an array of {GoogleContacts::Element} to be updated/created/deleted
    # @param [Array] list Array of elements
    # @param [GoogleContacts::List] list Array of elements
    # @param [Hash] args
    # @option args [Hash, Optional] :params Query string arguments when sending the API request
    # @option args [Hash, Optional] :headers Any additional headers to pass with the API request
    # @option args [Symbol, Optional] :api_type Override which part of the API is called, can either be :contacts or :groups
    #
    # @raise [Net::HTTPError]
    # @raise [GoogleContacts::InvalidResponse]
    # @raise [GoogleContacts::InvalidRequest]
    # @raise [GoogleContacts::InvalidKind]
    #
    # @return [GoogleContacts::List] List of elements with the results from the server
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

    def delete_photo!(element)
      begin
        http_request(:delete, URI(element.photo_uri), :headers => {"Content-Type" => "image/*", "If-Match" => "*"})
        true
      rescue RecordNotFound
        raise RecordNotFound unless @raise_not_found === false
        nil
      end
    end

    def update_photo!(element, file_name)
      if File.exists?(file_name) && File.file?(file_name) && MIME::Types.type_for(file_name).first.media_type == 'image'
        element.photo_content_type = MIME::Types.type_for(file_name).first.simplified
        File.open(file_name, "r+") do |f|
          element.photo_body = f.read
        end
        begin
          http_request(:put, URI(element.photo_uri), :body => element.photo_body, :headers => {"Content-Type" => element.photo_content_type, "If-Match" => "*"})
        rescue RecordNotFound
          raise RecordNotFound unless @raise_not_found === false
          nil
        end
      else
        return false
      end
    end

    def get_photo(element, file_name = nil)
      unless element.is_a?(GoogleContacts::Element)
        element = get(File.basename(element))
      end

      if element.photo_uri.present?
      photo_uri = URI(element.photo_uri)
        begin
          http_request_blk(:get, photo_uri, {}) do |content_type, body|
            element.photo_content_type = content_type
            element.photo_body = body
          end
          unless file_name.nil?
            file_name = Digest::MD5.hexdigest("#{Time.now.to_s}-#{rand(1000000)}") if file_name.empty?
            element.write_photo(file_name)
          end
          element.photo_body
        rescue RecordNotFound
          false
        end
      end
    end



    def http_request(method, uri, args)
      http_request_blk(method, uri, args) do |content_type, body|
        body
      end
    end


    private
    def http_request_blk(method, uri, args, &block)
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

      if response.code == "400" or response.code == "412"
        raise InvalidRequest.new("#{response.body} (HTTP #{response.code})")
      elsif response.code == "404"
        raise RecordNotFound.new("#{response.body} (HTTP #{response.code})")
      elsif response.code == "401"
        if self.client && self.reconnect
          self.client.try(:auth)
        else
          raise Unauthorized.new(response.message)
        end
      elsif response.code != "200" and response.code != "201"
        raise Net::HTTPError.new("#{response.message} (#{response.code})", response)
      end
      yield response.content_type, response.body
      response.body
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



    private
      def api_uri
        @api_uri || {}
      end
  end
end
