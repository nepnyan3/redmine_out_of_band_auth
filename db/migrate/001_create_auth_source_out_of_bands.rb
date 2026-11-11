class CreateAuthSourceOutOfBands < ActiveRecord::Migration[4.2]
  def change
    create_table :auth_source_out_of_bands do |t|
      t.integer :user_id, index: true
      t.string :verification_code

      t.timestamps
    end
  end
end
