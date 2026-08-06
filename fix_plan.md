# Altair Performance Remediation Plan

هذه الخطة موجهة إلى AI agent سيعمل على إصلاح مشاكل latency والـ tail latency
في Altair، مع الحفاظ على سلوك framework الحالي وعدم التضحية بالسلامة أو
الـ durability من أجل أرقام benchmark أفضل.

## 0. قواعد العمل الإلزامية

قبل أي تعديل:

1. اقرأ `AGENTS.md` كاملاً والتزم به.
2. نفّذ `git status --short` و`git diff --stat` وسجّل التغييرات الموجودة.
3. توجد تغييرات محلية في `examples/benchmark_k6` ونتائجها. لا تحذفها ولا
   تعمل عليها إعادة ضبط أو overwrite غير مقصود.
4. لا تعدّل ملفات benchmark أثناء إصلاح framework إلا إذا كانت الخطوة
   الحالية تتطلب ذلك بوضوح، وسجّل سبب كل تعديل.
5. لا تستخدم قياسات README أو نتائج قديمة كـ baseline. أنشئ baseline جديداً
   من commit واضح، مع حفظ config ونسخة Crystal ونتائج كل run.
6. لا تستخدم قيم SQL interpolated للبيانات. كل القيم يجب أن تبقى bind
   parameters، وكل identifiers تمر عبر `quote_identifier`.
7. لا تغيّر semantics الخاصة بالـ callbacks أو transactions أو durability
   بصمت. أي تغيير سلوكي يحتاج spec وCHANGELOG وتوثيق.
8. لا تعتبر benchmark ناجحاً إذا تحسن average بينما ساء p99 أو p99.9.

## 1. الحالة الأساسية والتحقق الأولي

### 1.1 حفظ baseline

نفّذ واحفظ المخرجات خارج git أو في ملف مؤقت:

```bash
git status --short
git diff --stat
crystal --version
crystal tool format --check src spec examples
crystal spec
```

إذا فشل `crystal spec` بسبب cache أو مشكلة compiler في البيئة:

- جرّب cache تحت `/tmp`.
- سجّل الخطأ الكامل والإصدار.
- شغّل targeted specs الممكنة.
- لا تدّعي أن tests فشلت بسبب framework قبل فصل مشكلة البيئة.

### 1.2 baseline وظيفي

شغّل على الأقل:

- كل specs الخاصة بـ `record`.
- `spec/record/connection_spec.cr`.
- `spec/record/permit_gate_spec.cr`.
- `spec/concurrency/semaphore_spec.cr`.
- integration specs الخاصة بالـ controller/server.
- PostgreSQL contract suite إذا كان `ALTAIR_TEST_PG_URL` متاحاً.

وثّق عدد examples وpending ووقت التنفيذ.

### 1.3 baseline أداء قابل للتفسير

أضف أداة أو instrumentation مؤقتة، ثم قِس منفصلاً:

- `/health` بدون DB.
- `GET` على primary key.
- `POST` insert بسيط.
- update بسيط.
- delete بسيط.
- write مع validation.
- write مع callbacks.
- delete مع `dependent: :destroy` و`:delete_all`.
- SQLite وPostgreSQL كل منهما بشكل مستقل.

لكل workload احفظ:

- throughput.
- p50 وp90 وp95 وp99 وp99.9 وmax.
- failed requests وtimeouts.
- pool open/idle/in-flight.
- checkout wait.
- SQL execution.
- request parsing وrendering.
- CPU وRSS وGC إن أمكن.

## 2. المرحلة الأولى: إصلاح قابلية القياس

لا تبدأ بتحسينات micro-optimization قبل أن تصبح مصادر التأخير قابلة للفصل.

### 2.1 فصل checkout time عن SQL time

طوّر instrumentation في `Altair::Record::Connection` بحيث يقدم على الأقل:

- وقت انتظار checkout.
- وقت تنفيذ statement داخل connection.
- وقت decoding/reading للنتائج.
- وقت transaction begin/commit/rollback.
- اسم adapter ونوع العملية (`query`, `insert`, `update`, `delete`).

حافظ على توافق `on_query` قدر الإمكان. إذا احتاجت API جديدة، أضف API
مستقلة مثل `on_query_event` بدلاً من كسر المستخدمين الحاليين.

المطلوب ألا يبدأ query timer قبل pool checkout، وألا يسمى زمن pool
"SQL duration".

### 2.2 قياس الفشل والـ timeout

كل event يجب أن يسجل completion أو failure في `ensure`، من غير تسجيل قيم
حساسة أو bind parameters.

أضف tests تثبت:

- hook يعمل عند النجاح.
- hook يعمل عند exception.
- checkout wait لا يدخل في SQL duration.
- transaction يحسب checkout مرة واحدة فقط.
- لا يحدث leak للـ connection أو permit عند exception.

### 2.3 pool metrics

اعرض أو وفّر instrumentation لـ:

- open connections.
- idle connections.
- in-flight connections.
- pool limit.
- عدد المنتظرين إن كان ممكناً.
- عدد pool timeouts.
- عدد gate timeouts.

يجب أن تكون metrics اختيارية ولا تضيف allocations أو clock reads في المسار
الافتراضي عند تعطيلها.

## 3. المرحلة الثانية: timeouts وbackpressure

### 3.1 تنفيذ `db_query_timeout` فعلياً

`config.db_query_timeout` موجود حالياً لكنه لا يُطبق. أصلحه بطريقة adapter-aware:

- PostgreSQL: طبّق statement timeout لكل connection أو لكل transaction بطريقة
  لا تلوث connection التالية، وراعِ reset عند release.
- SQLite: ميّز بين query timeout وbusy timeout. لا تدّع أن busy timeout
  يوقف query عامة؛ طبّق ما يسمح به driver فعلياً، أو ارفع configuration error
  واضحاً إذا كان الخيار غير قابل للتنفيذ في adapter معين.
- لا تستخدم thread يقتل query عشوائياً ويترك connection في حالة غير صالحة.
- عند timeout، أغلق أو discard connection إذا كان driver قد يترك transaction
  أو protocol في حالة غير آمنة.

أضف specs لـ:

- query تتجاوز timeout.
- connection تعود إلى pool بعد timeout.
- transaction تعمل rollback بعد timeout.
- لا يمكن لـ timeout أن يترك `idle in transaction`.
- PostgreSQL contract spec عند توفر PostgreSQL.

### 3.2 checkout deadline

افصل بين:

- `db_checkout_timeout` الخاص بالـ pool.
- timeout انتظار admission gate.
- request deadline الكلي.

أضف config واضحاً، مثلاً `db_admission_timeout` أو equivalent، بحيث لا ينتظر
request إلى ما لا نهاية داخل FIFO gate.

عند تجاوز deadline:

- حرر أي permit تم أخذه.
- لا تدخل pool إذا انتهت المهلة.
- أعد exception قابلة لتحويلها إلى 503/429 حسب policy موثقة.
- لا تسجل body أو headers الحساسة.

### 3.3 إصلاح semantics الخاصة بـ PermitGate

راجع `PermitGate` و`Semaphore` لتحديد contract واضح:

- gate يجب أن يحد active DB work فعلاً.
- لا يجب أن يكون limit أكبر من pool بلا معنى. إما clamp موثق أو validation
  يفشل عند boot.
- queue قد تكون FIFO، لكن لا تدّع أنها bounded latency بدون timeout.
- تبديل semaphore أثناء وجود requests يجب ألا يفقد permits أو يعلق fibers.
- أضف tests للـ cancellation/timeout وexception وconcurrent reconfiguration.

لا تجعل admission gate global بين تطبيقات أو قواعد بيانات مختلفة إذا كان
ذلك يخلط capacities؛ راجع global class state وأضف ownership واضحاً.

## 4. المرحلة الثالثة: إزالة contention الداخلي

### 4.1 إصلاح `Altair::Record.connection`

المطلوب fast path لا يأخذ mutex بعد initialization:

- القراءة السريعة للاتصال المنشأ.
- mutex فقط عند أول إنشاء أو close/reopen.
- double-check آمن عند first touch.
- لا تُستخدم قيمة قد تصبح dangling بعد `close_connection`.

أضف specs لـ:

- first-touch concurrent initialization يفتح pool واحداً.
- مئات fibers تحصل على نفس connection object/pool.
- close ثم reopen لا يسبب race.
- transactions لا تتأثر.

قِس قبل وبعد عدد mutex operations في workload عالي التوازي.

### 4.2 مراجعة locks الأخرى

راجع:

- transaction maps.
- N+1 detector.
- query handlers.
- checkout handlers.
- pool mutex في `crystal-db`.

لا تزل synchronization من state قابل للتغيير. الهدف تقليل lock scope وليس
إخفاء race condition.

## 5. المرحلة الرابعة: prepared statements ومسار SQL

### 5.1 PostgreSQL prepared statements حقيقية

تحقق من إمكانيات `lib/pg` و`crystal-pg` الحالية. نفّذ named prepared
statements لكل physical connection مع:

- اسم ثابت وآمن مشتق من query fingerprint.
- cache محدود أو eviction policy واضحة.
- invalidation عند connection reconnect.
- عدم مشاركة statement بين physical connections.
- fallback آمن إذا كان query dynamic أو driver لا يدعمه.

لا تجعل كل SQL متغير بسبب اختلاف عدد placeholders إلا عند الضرورة.

أضف tests أو protocol-level verification تثبت أن query المتكرر لا يرسل
Parse/Describe كاملين في كل مرة، إن كان driver يسمح بذلك.

قارن:

- statement cache off.
- default current behavior.
- named prepared cache.

قارن throughput وp99، وليس average فقط.

### 5.2 تقليل SQL generation والـ allocations

في model macros:

- اجعل INSERT SQL ثابتاً قدر الإمكان ومولداً compile-time.
- cache quoted table/column names.
- لا تعيد بناء نفس placeholder lists في كل request.
- حافظ على dirty tracking في UPDATE.
- لا تغيّر bind safety.

أضف benchmark صغير لمسار `create` و`update` يقيس allocations إن أمكن.

## 6. المرحلة الخامسة: إصلاح مسار الكتابة

### 6.1 JSON parsing مرة واحدة

عدّل `HTTP::Request` وController API بحيث:

- JSON يُحلل lazy أو مرة واحدة فقط.
- controller يستخدم `request.json` أو typed body accessor.
- لا يتم تحويل كل JSON scalars إلى strings ما لم يطلب التطبيق `params`.
- malformed JSON ينتج behavior موثقاً ومتسقاً.

أضف specs تثبت:

- JSON parse يحدث مرة واحدة.
- nested JSON يبقى متاحاً.
- form params لا تتأثر.
- precedence بين route/query/form/json لا تتغير.

### 6.2 uniqueness validation

حسّن validation بحيث:

- توثق أنها optimization لا guarantee.
- تقترح أو تتحقق من unique index في schema.
- لا تنفذ query إذا كانت القيمة غير معدلة في update.
- تستفيد من prepared statement ثابت.
- تتعامل مع constraint violation كحالة validation مناسبة.

أضف spec لعدم تكرار uniqueness query عند no-op update، وspec لـ race
بين recordين على PostgreSQL.

### 6.3 transaction overhead

راجع policy لكل عملية:

- plain insert/update بلا callbacks: statement واحد حيثما أمكن.
- plain delete بلا callbacks أو dependent behavior: لا transaction إضافية
  إذا كان ذلك آمناً.
- callbacks وdependent behavior: حافظ على atomicity.
- لا تجعل callback يفتح nested transaction غير ضرورية.

أضف query-count specs لكل مسار، مع الحفاظ على rollback semantics.

### 6.4 dependent deletion

أبقِ `dependent: :destroy` callback semantics كما هي، لكن حسّن الحالات:

- `:delete_all`: bulk DELETE واحد.
- `:nullify`: bulk UPDATE واحد.
- `:destroy`: وضّح cost per child وقياسه.
- تجنب savepoint لكل child إذا كان parent transaction موجوداً ويمكن تنفيذ
  destroy callback بدون transaction wrapper إضافي.
- أضف حماية من parent له آلاف children، مع instrumentation يوضح amplification.

## 7. المرحلة السادسة: SQLite write path

### 7.1 writer admission

أضف policy صريحة لـ SQLite:

- خيار `db_max_active_writes` أو equivalent.
- default محافظ لا يسمح بتنافس writers غير المحدود.
- لا تمنع القراءات بلا داعٍ عند استخدام WAL.
- لا تطبق تحسيناً يقلل durability بصمت.

### 7.2 durability وPRAGMA configuration

اجعل الخيارات المهمة قابلة للتهيئة، مثل:

- `journal_mode`.
- `synchronous`.
- `busy_timeout`.
- WAL checkpoint policy.

يجب أن تبقى default values آمنة ومُوثقة. أضف adapter specs تتحقق من
القيم الفعلية، لا من config فقط.

### 7.3 SQLite tests

اختبر:

- concurrent writes.
- read/write concurrency في WAL.
- busy timeout.
- writer timeout.
- connection cleanup بعد SQLite error.
- عدم ظهور `SQLITE_BUSY` غير متوقع تحت load محدود.

## 8. المرحلة السابعة: pool sizing وgeneral HTTP latency

### 8.1 pool defaults

راجع العلاقة بين:

- `db_initial_pool_size`.
- `db_max_idle_pool_size`.
- `db_max_pool_size`.

لا تستخدم `max_idle=2` مع `max_pool=10` كـ warm pool بدون دليل قياسي.
إما اجعل max idle قريباً من max pool في sustained workloads، أو وثق أن
الإغلاق مقصود وقدم config profile للـ burst workloads.

أضف pool churn benchmark يقيس connection opens/closes لكل دقيقة.

### 8.2 request logger

اجعل request logging قابلاً لـ:

- disable في production.
- sampling.
- مستوى log مختلف للـ health checks.
- عدم جعل sink بطيئاً يوقف request fibers.

أضف benchmark `/health` مع logger enabled/disabled.

### 8.3 static middleware

حسّن static serving بحيث:

- لا يقرأ الملف كاملاً إلى الذاكرة.
- يستخدم streaming أو sendfile-compatible path.
- يضيف cache headers وETag عند الحاجة.
- لا يفحص filesystem لكل API request إذا كان static path prefix معروفاً.

أضف benchmark لملفات صغيرة وكبيرة مع p99 وRSS.

### 8.4 request body handling

لا تقرأ أو تحلل body أكثر مما يحتاجه route. حافظ على max body size وchunked
request protection. أضف tests لعدم استهلاك body مرتين.

## 9. اختبار correctness والـ regression

كل إصلاح يحتاج spec قبل أو مع الإصلاح، وتشمل المجموعة:

- connection initialization races.
- connection close/reopen races.
- checkout timeout.
- query timeout.
- gate timeout وpermit release.
- query timing separation.
- query hooks عند failure.
- PostgreSQL named preparation.
- JSON parse مرة واحدة.
- no-op update.
- uniqueness/index behavior.
- callback transaction rollback.
- dependent deletion.
- SQLite concurrent writes.
- static streaming.
- logger disabled/sampled.

شغّل بعد كل مرحلة:

```bash
crystal tool format --check src spec examples
crystal spec
crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent
```

شغّل PostgreSQL contract suite مع `ALTAIR_TEST_PG_URL`، ولا تعتبر pending
الخاص بها نجاحاً كاملاً لمسار PostgreSQL.

## 10. benchmark protocol النهائي

أنشئ benchmark matrix ثابتة:

### Workloads

- health/no DB.
- PostgreSQL read.
- PostgreSQL single-row insert.
- PostgreSQL update.
- PostgreSQL delete.
- SQLite read.
- SQLite write.
- validation write.
- callback write.
- large cascade delete.

### Configurations

- pool صغير.
- pool متوسط.
- pool كبير.
- admission gate off.
- gate مساوي للـ pool.
- gate أقل من pool.
- prepared cache off/current.
- prepared cache on.
- logger/static enabled.
- logger/static disabled.

### Protocol

- نفس commit ونفس binary لكل run.
- نفس CPU/memory limits.
- PostgreSQL منفصل عن host عند الإمكان.
- warm-up منفصل ولا يدخل percentiles النهائية.
- sustained phase ثابتة.
- خمس runs على الأقل لكل configuration.
- أبلغ median وrange بين runs.
- لا تقارن تطبيقات تغيرت محلياً دون تسجيل ذلك.
- احفظ raw k6 JSON وserver logs وDB metrics.

### Acceptance targets

لا تستخدم أرقاماً مطلقة قبل baseline، لكن يجب تحقيق الآتي:

- لا query تتجاوز timeout المحدد وتحتجز pool بلا نهاية.
- لا gate waiter ينتظر بلا deadline.
- لا connection leak بعد query/transaction timeout أو exception.
- p99 وp99.9 يتحسنان تحت pool saturation مقارنة بـ baseline.
- write p99 لا يسوء في الحمل الطبيعي.
- SQLite لا ينهار إلى busy/timeout تحت الحمل المدعوم.
- no regression في throughput ضمن هامش متفق عليه.
- جميع specs وformatter وAmeba خضراء.

## 11. التوثيق والتسليم

حدّث:

- `CHANGELOG.md` تحت `[Unreleased]`.
- `docs/architecture/performance-audit.md` مع فصل findings القديمة عن
  findings التي أُغلقت فعلياً.
- docs الخاصة بـ Record وconfiguration.
- benchmark README بحيث يطابق scripts والنتائج الفعلية.

في نهاية التنفيذ، سلّم تقريراً يحتوي على:

1. قائمة الملفات المعدلة.
2. كل issue وما إذا كان fixed أو deferred مع السبب.
3. قبل/بعد لكل p50/p95/p99/p99.9/max.
4. query count وcheckout wait وSQL time.
5. عدد الاتصالات المفتوحة وconnection churn.
6. نتائج SQLite وPostgreSQL بشكل منفصل.
7. أوامر الاختبار ومخرجاتها.
8. أي قيود بيئية أو pending specs.

لا تعتبر المهمة مكتملة بمجرد أن تمر specs؛ يجب أن تثبت القياسات أن tail
latency أصبح قابلاً للتوقع وأن مسار الكتابة لم يعد يحتجز pool أو يضيف
round trips غير ضرورية.
