class CreateItems < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:items) do |t|
      t.string :name, null: false
      t.float :price, null: false
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:items)
  end
end
