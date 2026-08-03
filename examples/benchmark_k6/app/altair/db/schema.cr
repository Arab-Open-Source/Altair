# db/schema.cr - compile-time column metadata for the benchmark model. The
# table itself is built by the compose init script (db/init.sql); the Record
# model macros consume this constant at compile time.
class Altair::Record::Schema
  META = {
    items_altair: {
      id:    {type: :integer, null: false, primary: true},
      name:  {type: :string, null: false, primary: false},
      price: {type: :float, null: false, primary: false},
    },
  }
end

Altair::Record::Schema.define do |schema|
  schema.table(:items_altair) do |t|
    t.column :id, :integer, null: false, primary: true
    t.column :name, :string, null: false, primary: false
    t.column :price, :float, null: false, primary: false
  end
end