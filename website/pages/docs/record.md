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

### Bulk inserts, dirty tracking and enum columns

```crystal
# One multi-row INSERT; timestamps auto-fill like create. Bypasses
# validations and callbacks — this is the bulk load path. Large sets
# chunk inside one transaction, so the call stays all-or-nothing.
Post.insert_all([
  {title: "a", views: 1, published: true},
  {title: "b", views: 2, published: false},
])

post = Post.find!(1)
post.changed?                    # any attribute changed since load?
post.changed_attributes          # [:title]
post.attribute_changed?(:views)  # false
post.restore_attributes(:title)  # revert to the loaded value
post.restore_attributes          # or every changed attribute

# A string column with a compile-time checked value set:
class Task < Altair::Record::Model
  table :tasks

  enum_attribute :state, [:pending, :in_review, :done]
end

task.state = Task::State::Done   # compiles
task.state = "done"              # compile error
```

`enum_attribute` stores the member name in snake_case (`"in_review"`),
so raw rows stay readable; a stored value no member claims reads back as
`nil`, keeping legacy data safe.

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

### Loading and counting without N+1

Association accessors are lazy: `post.comments` runs one query the first
time it is touched. That is free for a single record and quietly
catastrophic inside a loop — `posts.each { |p| p.comments.size }` is one
query per post. The rule: **an association accessed inside a loop belongs
in `includes`**.

```crystal
posts = Post.all.includes(:comments).to_a   # one batched query per association
posts.each { |p| p.comments.size }          # no extra queries
```

`includes` nests through named pairs — every further level applies to the
rows the previous level loaded, still one batched query per level:

```crystal
User.all.includes(posts: :comments).to_a
User.all.includes(posts: {comments: :post}).to_a   # any depth
```

`Relation#count` and `size` never materialize the rows — they run
`COUNT(*)` with the scoped `where` clauses (and reuse the cached rows once
loaded):

```crystal
Post.all.where(published: true).count       # SELECT COUNT(*), no row loading
Post.all.includes(:comments).size           # 2 queries, rows not materialized
```

### Scopes

A `scope` declares a reusable, chainable query fragment as a class
method. The static form passes `key: value` pairs to `where`; the block
form receives the relation and returns whatever chain it builds:

```crystal
class Post < Altair::Record::Model
  table :posts

  scope :published, published: true
  scope :recent { |query| query.order(:created_at).limit(10) }
end

Post.published.to_a
Post.recent.where(:views, :>=, 5).to_a
```

Crystal has no dynamic dispatch, so two scopes compose through
`merge` — where clauses AND together and a later `order`, `limit` or
`offset` wins:

```crystal
Post.published.merge(Post.recent).to_a
```

`find_each` streams in bounded batches ordered by primary key and keeps
the scoped filters and preloaders across batches:

```crystal
Post.all.where(published: true).includes(:comments).find_each(batch_size: 100) do |post|
  post.comments.each { |c| c.touch }
end
```

In the Development environment the framework watches every query for the
N+1 signature — the same SQL firing more than `config.n_plus_one_threshold`
(3) times within one request — and logs a warning naming the statement.
Production never pays the detector's cost; disable it with
`config.detect_n_plus_one = false` if it is ever noisy.

## Joins

Filter parents by their children in a single SQL query — no N+1, no manual SQL:

```crystal
Post.all.joins(:comments).where("comments.body", "altair")
Post.all.left_joins(:comments)                 # keep owners without children
Post.all.joins(:comments).where("comments.body", "hi").count   # COUNT(DISTINCT posts.id)
```

`joins` on a `has_many` automatically deduplicates (`SELECT DISTINCT`) so a post
with three matching comments appears once. Qualified columns (`"comments.body"`)
are quoted per part; every value is still a bind parameter.

## Ordering & reloading

```crystal
Post.all.order(:created_at).order(:title)       # ORDER BY created_at, title (accumulates)
Post.all.order(:created_at).reorder(:title)     # ORDER BY title (replaces)
Post.all.unscope_order                          # removes all ORDER BY

post = Post.find!(1)
post.reload                                     # re-reads from DB
```

## Custom primary keys

```crystal
table :posts, primary_key: :uuid   # column must exist in the migration
```

String PKs auto-generate a `SecureRandom.uuid` before insert. All finders,
loaders, updates and deletes respect the custom name.

## has_many :through
## has_many :through

```crystal
class Post < Altair::Record::Model
  has_many :post_tags
  has_many :tags, through: :post_tags     # source inferred (:tag)
end

post.tags                                  # lazy: one JOIN query
Post.all.includes(:tags)                   # eager: one batched JOIN for all posts
Post.all.joins(:tags).where("tags.name", "crystal")
```

Pass `source:` explicitly when the singular name is ambiguous — the framework
raises at boot asking for it rather than guessing.

## Polymorphic associations

```crystal
class Comment < Altair::Record::Model
  belongs_to :commentable, polymorphic: true   # commentable_id + commentable_type
end

class Post < Altair::Record::Model
  has_many :comments, as: :commentable, dependent: :destroy
end
class Video < Altair::Record::Model
  has_many :comments, as: :commentable, dependent: :nullify
end

comment.commentable        # Post or Video, resolved from the type column
post.comments              # filtered by notable_type = 'Post'
Post.all.includes(:comments)   # one batched query per distinct type
```

Migrations get a helper too:

```crystal
schema.create_table(:comments) do |t|
  t.string :body
  t.references :commentable, polymorphic: true   # id + type + composite index
end
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

## Performance defaults

Altair ships performance-sane defaults, all overridable through `config`:

- The server resizes Crystal's execution context to the available workers
  on boot, so requests fan out across cores instead of running on the
  single OS thread the runtime starts with. Set the `CRYSTAL_WORKERS`
  environment variable to your CPU limit inside containers; disable with
  `config.parallel_execution = false`.
- The connection pool opens warm and stays warm —
  `db_initial_pool_size 2`, `db_max_idle_pool_size 2`,
  `db_max_pool_size 10` — avoiding connection-creation bursts and
  reconnect churn under load. Tune with the `config.db_*` properties.
