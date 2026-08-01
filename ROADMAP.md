# Altair Roadmap

> **Philosophy:** Every phase ends with something working and visible — vertical slices, not horizontal scaffolding. Each phase has a clear exit criterion.

## Phase 0: Foundation (~1 week)
| Task | Exit criterion |
|---|---|
| Set up `Altair::App` on top of `HTTP::Server` | First request returns "Hello Altair" |
| Request/Response abstractions + params | Query params and body are readable |
| Configuration system (`Altair.configure`) | Settings load from file |

## Phase 1: Router (the heart) ⚡ (~1 week)
| Task | Exit criterion |
|---|---|
| Routing DSL: `get/post/put/patch/delete` + `namespace` | Routes written naturally |
| Path params (`:id`) | `/users/5` yields `params["id"] == "5"` |
| Named routes (like `user_path`) | Paths callable by name |
| `resources` macro | One line generates 7 REST routes |
| 404/405 handling | Wrong path returns proper response |

## Phase 2: Controllers (~half week)
| Task | Exit criterion |
|---|---|
| `BaseController`: render, redirect, params | Full controller works |
| Middleware pipeline | Logger + static files |

## Phase 3: Views — ECR++ 🎨 (~1 week)
| Task | Exit criterion |
|---|---|
| Auto-escaping by default (`<%= %>` escapes, `<%== %>` raw) | XSS-safe out of the box |
| Layouts + `yield` | Pages share header/footer |
| Partials (`render "form"`) | File reuse |
| Helpers: `link_to`, `content_tag`, basic form builder | **Live HTML demo viewable in the browser** |

## Phase 4: CLI — `altair new` 🛠️ (~half week)
| Task | Exit criterion |
|---|---|
| `altair new blog` | Generates the standard project layout: `app/`, `config/`, `db/` |
| `altair server` | Single command to run |
| `altair routes` | Prints routes like `rake routes` |

## Phase 5: ORM — `Altair::Record` (the big one) 🗄️ (~3–4 weeks)
| Task | Exit criterion |
|---|---|
| Connection + config (SQLite first, PG ready) | App connects to DB |
| Migrations DSL + `db:migrate` / `db:rollback` | Table created and dropped |
| **`schema.cr` generation** | Wrong column = compile error ⭐ |
| CRUD + finders (`find_by_*`) | Natural row handling |
| Validations | `valid?` + errors |
| Associations: `belongs_to` / `has_many` / `has_one` | `user.posts` works |
| Callbacks + Transactions | Automatic saves + safe operations |

## Phase 6: The magic moment 🪄 (~1 week)
| Task | Exit criterion |
|---|---|
| `altair g model/migration/controller` | Ready-to-edit files generated |
| **`altair g scaffold Post title:string body:text`** | **Full generator: model + migration + controller + views — everything works** |
| Full blog demo (scaffold + validations + associations) | `altair new blog && g scaffold && server` = framework magic |

## Phase 7: Feeling at home (~2 weeks)
| Task | Exit criterion |
|---|---|
| Sessions + flash + CSRF | Simple login works |
| Beautiful error pages in dev | Fast debugging experience |
| `database.yml` / .env config | Production-ready project |
| Maintenance: Ameba (linter) + specs everywhere | Real project quality |

## Phase 8: v2 (post first release)
Background jobs • Full auth • Asset pipeline • Rich query DSL (joins, preload, scopes) • Testing utilities • `has_many :through` • Polymorphic associations

---

## Realistic Estimate
**3.5 – 5 months** of serious work to reach v0.1 (blog demo + scaffold + core ORM). The ORM will consume ~40% of the time — expected, it's the heart.

## Golden Rules
1. **Specs from day one** — each phase ends with its specs passing
2. **Never skip a phase's exit criterion** — building the ORM before a working demo exists is wasted effort
3. **Every week, something visible** — eyes on the demo, not just internals
4. **Hold off the complex 20%** — polymorphic and STI come after the first release, not before
