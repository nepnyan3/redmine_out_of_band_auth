class IntegrateNativeTwofa < ActiveRecord::Migration[7.2]
  def up
    # Old codes are intentionally invalidated; never migrate plaintext secrets.
    execute 'DELETE FROM auth_source_out_of_bands'
    remove_column :auth_source_out_of_bands, :verification_code, :string
    add_column :auth_source_out_of_bands, :code_digest, :string
    add_column :auth_source_out_of_bands, :expires_at, :datetime
    add_column :auth_source_out_of_bands, :sent_at, :datetime
    add_column :auth_source_out_of_bands, :attempts, :integer, null: false, default: 0
    remove_index :auth_source_out_of_bands, :user_id
    add_index :auth_source_out_of_bands, :user_id, unique: true

    migrated = false
    User.find_each do |user|
      next unless user.pref[:enabled_out_of_band_auth] == '1'
      # An existing TOTP (or another registered scheme) always wins.
      if user.twofa_scheme.blank?
        user.update!(twofa_scheme: 'email')
        migrated = true
      end
    end
    # Native confirmation routes must be available to migrated email users.
    Setting.twofa = '1' if migrated && !Setting.twofa?
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Restore the pre-upgrade database backup to return to the legacy authentication flow.'
  end
end
