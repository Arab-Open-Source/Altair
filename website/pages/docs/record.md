# Record (ORM)

`Altair::Record` is the ORM: SQLite3 and PostgreSQL adapters behind one
interface, a migrations DSL, compile-time column metadata, validations,
callbacks and associations. Every value travels as a bind parameter — SQL
strings stay constant, so values can never be interpolated into a query.

## Connecting

The application points at a database; `ALTAIR_DB_URL` overrides it at run
time:

```crystal
class Blog < Altair::Application
  config.db_url = ENV["ALTAIR_DB_URL"]? || "sqlite3://./db/blog.db"
end
```

```sh
# SQLite (default) — or PostgreSQL:
ALTAIR_DB_URL="postgres://postgres:secret@localhost:5433/blog" altair server
```

## Models

A model maps to a table and gets typed accessors for every column, generated
from `db/schema.cr` at compile time:

```crystal
class Post < Altair::Record::Model
  table :posts

  has_many :comments, dependent: :destroy
  validates_presence_of :title
end
```

### CRUD and finders

```crystal
post = Post.new(title: "Hello")
post.save                                  # false when invalid
post.save!                                 # raises Altair::Record::Error instead

Post.create(title: "Hello")                # save + validate, one call
post.title = "Edited"
post.update(title: "Edited")               # save changes in place
post.delete                                # delete the row

Post.find(5)                               # Post?  — nil when missing
Post.find!(5)                              # Post   — raises when missing
Post.find_by_title("Hello")                # Post?  — find_by_<column>
Post.find_by_title!("Hello")
Post.all                                   # Relation(Post)
Post.count                                 # Int64
Post.exists?(5)
Post.pluck(:title)                         # Array(Value)
```

`Post.all` is lazy and caches after iteration; chain `.where` to filter:

```crystal
Post.all.where(published: true)
Post.all.where(:views, :>=, 15).order(:created_at).to_a
```

## Migrations

Migrations live in `db/migrations/` as timestamped files; `altair
db:migrate` runs pending ones and `altair db:rollback` undoes the last.

```crystal
class CreatePosts < Altair::Record::Migration
  def up(schema : Altair::Record::Schema) : Nil
    schema.create_table(:posts) do |t|
      t.string :title
      t.text :body
      t.boolean :published
      t.datetime :created_at
      t.datetime :updated_at
    end
    schema.add_index(:posts, :title)
  end

  def down(schema : Altair::Record::Schema) : Nil
    schema.drop_table(:posts)
  end
end
```

Column types are `string`, `text`, `integer`, `bigint`, `float`, `decimal`,
`boolean`, `datetime` and `json`. Timestamps aren't automatic — add
`created_at` / `updated_at` columns and the model fills them when they
exist. `db/schema.cr` is regenerated after every run and feeds the
compile-time column metadata, so the model's accessors always match the
database.

## Validations

Validations run before save; failures land in `errors` and `valid?` returns
false:

```crystal
class Post < Altair::Record::Model
  validates_presence_of :title
  validates_length_of :title, maximum: 140
  validates_numericality_of :views, greater_than: 0, integer: true
  validates_uniqueness_of :slug, scope: :category_id
  validates_inclusion_of :status, in: %w[draft published]
  validates_exclusion_of :slug, in: %w[admin login]
  validates_format_of :email, with: /\A[^@\s]+@[^@\s]+\z/
  validates_confirmation_of :password
end
```

```crystal
post = Post.new(title: "")
post.valid?            # false
post.errors[:title]    # ["Title can't be blank"]
post.errors.full_messages
```

## Callbacks

`before_save`, `after_save`, `before_create`, `after_create`,
`before_update`, `after_update`, `before_destroy`, `after_destroy` — each
takes method names to run around the lifecycle:

```crystal
class Post < Altair::Record::Model
  before_save :slugify
  after_create :notify

  private def slugify : Nil
    self.slug = title.downcase.gsub(' ', "-")
  end
end
```

## Associations

`belongs_to`, `has_many` and `has_one` generate typed accessors and foreign
keys. `dependent:` clears the child rows when the parent is destroyed, and
`includes` eager-loads a whole relation in one batched query — no query per
row:

```crystal
class Post < Altair::Record::Model
  has_many :comments, dependent: :destroy
  has_one :profile
end

class Comment < Altair::Record::Model
  belongs_to :post
end
```

```crystal
post.comments.each { |c| puts c.body }
Post.all.includes(:comments).to_a          # 2 queries total
```

## Transactions

`transaction` runs its block atomically; a raise rolls it back:

```crystal
Post.transaction do
  post.save!
  comment.save!
end
```

## Adapters

SQLite3 ships in the framework; PostgreSQL is enabled by requiring the
adapter and `crystal-pg` in the project's shard:

```crystal
require "altair/record/adapters/postgresql"
```

The same application code runs on either — the adapter interface is the
only thing that changes.
