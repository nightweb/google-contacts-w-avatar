module GoogleContacts
  module Auth
    class UserLogin

      attr_accessor :client, :token, :username, :password, :email, :reconnect, :not_init_google_contacts

      def initialize(username, password, args={})
        @email=args[:email]
        @reconnect=args[:reconnect]
        @username = username
        @password = password
        @email = email
        auth(username, password, args)
      end

      def google_contacts=(object)
        if object.is_a?(Boolean) && object === false
          @not_init_google_contacts = true
        end
        @google_contacts = object
      end

      def google_contacts
        unless @not_init_google_contacts || @google_contacts.present?
          @google_contacts = GoogleContacts::Client.new(access_token: token, user_email: args[:email] || @email, auth_header: "GoogleLogin auth=#{@token}", gdata_version: '2.0', reconnect: args[:reconnect] || @reconnect )
          @google_contacts.client = self
        end
        @google_contacts
      end

      def auth(username = nil, password = nil, args={})
        @client = GData::Client::Contacts.new
        @token = @client.clientlogin(username || @username, password || @password)
        @client
      end
    end
  end
end