module GoogleContacts
  module Auth
    class UserLogin

      attr_accessor :client, :token, :username, :password, :email

      def initialize(username, password, args={})
        email=args[:email]
        reconnect=args[:reconnect]
        @username = username
        @password = password
        @email = email
        auth(username, password, email)
      end

      def auth(username = nil, password = nil, email = nil)
        @client = GData::Client::Contacts.new
        @token = @client.clientlogin(username || @username, password || @password)
        @google_contacts = GoogleContacts::Client.new(access_token: token, user_email: email || @email, auth_header: "GoogleLogin auth=#{@token}", gdata_version: '2.0', reconnect: reconnect )
        @google_contacts.client = self
        @google_contacts
      end

    end
  end
end