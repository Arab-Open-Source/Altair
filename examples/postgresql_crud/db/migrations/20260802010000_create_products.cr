# Creates the products table used by the CRUD example.
class CreateProducts < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:products) do |table|
      table.string :name, null: false
      table.float :price, null: false
      table.datetime :created_at
      table.datetime :updated_at
    end
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:products)
  end
end
