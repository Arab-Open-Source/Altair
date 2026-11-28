# Record (ORM)

`Altair::Record` is compile-time checked against `db/schema.cr`, which the
migration runner regenerates. Never hand-edit the schema file.

## Models and schema

```crystal
class Post < Altair::Record::Model
  table :posts
  scope :published, published: true
end

post = Post.create(title: "Hi")
Post.find(1)        # nil when missing
Post.find!(1)       # raises RecordNotFound
post.changed?       # dirty tracking
```

A wrong column name is a compile error because the `table` macro reads the
generated schema metadata.

## Associations

```crystal
class Post < Altair::Record::Model
  table :posts
  has_many :comments, dependent: :destroy
  has_many :tags, through: :post_tags
end

class Comment < Altair::Record::Model
  table :comments
  belongs_to :post
end
```

`belongs_to`, `has_many`, `has_one`, `has_many :through` and polymorphic
associations are supported. `Relation#includes` batches preloads; `joins`
filters parents by child rows in one query.

## Validations

`validates_presence_of`, `validates_uniqueness_of`, `validates_length_of`,
numericality, inclusion, exclusion, format, confirmation and custom
`validate` blocks are available. `valid?` populates `errors`; `save` returns
false on failure and `save!` raises.

## Queries

```crystal
Post.all.where(published: true).where(:views, :>, 10).order(:title).limit(5).to_a
Post.all.where(:title, :like, "%altair%")
Post.all.left_joins(:comments)
Post.all.ids
Post.all.exists?
```

Every value travels as a bind parameter — never interpolate values into SQL.
`find_each` streams batches with filters and preloads intact, and `count`
uses `COUNT(*)` without materializing rows. `update_all`, `delete_all`,
`insert_all` and `upsert` perform bulk writes.

## Transactions

```crystal
Post.transaction do
  post.save!
  Comment.create!(post_id: post.id)
end
```

Savepoints support nested transactions. `after_commit` fires only when the
transaction lands; `after_rollback` fires when it unwinds. Enqueue jobs in
`after_commit`, not `after_save`.

## Migrations

Apply them explicitly with `bin/altair db:migrate`;
`bin/altair db:rollback` reverts one step. Migrations never run automatically
at server boot or container start. Generated migrations are compiled into
the command binary, so schema changes require a rebuild as well as a
migration.
