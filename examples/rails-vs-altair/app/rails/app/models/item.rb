# Rails vs Altair benchmark — the single persisted entity, mirroring the
# Altair Item model (id, name, price against table items_rails).
class Item < ApplicationRecord
  self.table_name = "items_rails"

  validates :name, presence: true
  validates :price, presence: true, numericality: true
end