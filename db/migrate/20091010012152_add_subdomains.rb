class AddSubdomains < ActiveRecord::Migration
  def self.up
    create_table :subdomains do |t|
      t.string :name
      t.timestamps
    end
    add_column :rubygems, :subdomain_id, :integer
    add_index  :rubygems, :subdomain_id

    create_table :subdomains_users, :id => false do |t|
      t.references :subdomain
      t.references :user
      t.timestamps
    end
    add_index :subdomains_users, :subdomain_id
    add_index :subdomains_users, :user_id
  end

  def self.down
    remove_index :subdomains_users, :user_id
    remove_index :subdomains_users, :subdomain_id
    drop_table   :subdomains_users

    remove_index  :rubygems, :subdomain_id
    remove_column :rubygems, :subdomain_id
    drop_table    :subdomains
  end
end
