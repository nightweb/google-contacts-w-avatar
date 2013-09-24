module GoogleContacts
  module Auth
    class UserLogin
      attr_accessor :client, :token

      def initialize(username, password)
        @client = GData::Client::Contacts.new
        @token = @client.clientlogin(username,password)
        GoogleContacts::Client.new(:access_token => token, )
      end

    end
  end
end