# frozen_string_literal: true

# LocalUser provides a User-compatible interface for local/standalone mode.
#
# In local mode, SmartSuite credentials come from environment variables
# instead of the database. This allows running the server without
# user management infrastructure.
#
# @example
#   # With environment variables set:
#   # SMARTSUITE_API_KEY=your_key
#   # SMARTSUITE_ACCOUNT_ID=your_account
#
#   user = LocalUser.from_env
#   user.smartsuite_api_key    #=> "your_key"
#   user.smartsuite_account_id #=> "your_account"
#
class LocalUser
  attr_reader :id, :name, :email, :smartsuite_api_key, :smartsuite_account_id

  def initialize(api_key:, account_id:, name: nil, email: nil)
    @id = 'local'
    @name = name || 'Local User'
    @email = email || ENV.fetch('SMARTSUITE_USER_EMAIL', 'local@localhost')
    @smartsuite_api_key = api_key
    @smartsuite_account_id = account_id
  end

  # Create a LocalUser from environment variables
  #
  # @return [LocalUser] configured from environment
  # @raise [RuntimeError] if required environment variables are missing
  def self.from_env
    api_key = ENV.fetch('SMARTSUITE_API_KEY') do
      raise 'SMARTSUITE_API_KEY environment variable is required in local mode'
    end

    account_id = ENV.fetch('SMARTSUITE_ACCOUNT_ID') do
      raise 'SMARTSUITE_ACCOUNT_ID environment variable is required in local mode'
    end

    new(
      api_key: api_key,
      account_id: account_id,
      name: ENV.fetch('SMARTSUITE_USER_NAME', 'Local User'),
      email: ENV.fetch('SMARTSUITE_USER_EMAIL', nil)
    )
  end

  # Check if environment is configured for local mode
  #
  # @return [Boolean] true if required env vars are present
  def self.env_configured?
    ENV['SMARTSUITE_API_KEY'] && ENV['SMARTSUITE_ACCOUNT_ID']
  end
end
