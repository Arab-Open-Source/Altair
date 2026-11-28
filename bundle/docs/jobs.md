# Background jobs

Jobs declare typed parameters, so `enqueue` is compile-checked:

```crystal
class SendEmailJob < Altair::Jobs::Job
  params user_id : Int64, subject : String

  def perform : Nil
    # work here
  end
end

SendEmailJob.enqueue(user_id: 1_i64, subject: "Hi")
SendEmailJob.enqueue_in(2.hours, user_id: 1_i64, subject: "Hi")
```

The `altair_jobs` table is created lazily. Workers claim jobs atomically, so
concurrent workers never run the same job twice. Failed jobs retry with
exponential backoff up to `config.jobs_max_attempts` (default 5). Run a worker
with `bin/altair jobs:work` and inspect counts with `bin/altair jobs:stats`.
