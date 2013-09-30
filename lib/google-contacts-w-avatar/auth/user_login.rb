module GoogleContacts
  module Auth
    class UserLogin

      attr_accessor :client, :token, :username, :password, :email, :reconnect, :not_init_google_contacts, :init_args

      def initialize(username, password, args={})
        @email=args[:email]
        @reconnect=args[:reconnect]
        @username = username
        @password = password
        @email = email
        @init_args = args
        auth(username, password, args)
      end

      def google_contacts=(object)
        if object.is_a?(Boolean) && object === false
          @not_init_google_contacts = true
        end
        @google_contacts = object
      end

      def google_contacts(args={})
        unless @not_init_google_contacts || @google_contacts.present?
          init_google_contacts!(args)
          @google_contacts.client = self
        end
        @google_contacts
      end

      def auth(username = nil, password = nil, args={})
        args = @init_args.merge(args)
        @client = GData::Client::Contacts.new
        @token = @client.clientlogin(username || @username, password || @password, args[:captcha_token], args[:captcha_answer], args[:service], args[:account_type])
        @client
      end

      private
        def init_google_contacts!(args={})
          args = @init_args.merge(args)
          @google_contacts = GoogleContacts::Client.new(access_token: @token, user_email: init_args[:email] || @email, auth_header: "GoogleLogin auth=#{@token}", gdata_version: '3.0', reconnect: args[:reconnect] || @reconnect )
        end

    end
  end
end