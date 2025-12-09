class AddPasswordDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_digest, :string
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
