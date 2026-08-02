# Product persisted through Altair::Record.
class Product < Altair::Record::Model
  table :products

  validates_presence_of :name
  validates_numericality_of :price, greater_than: 0
end
