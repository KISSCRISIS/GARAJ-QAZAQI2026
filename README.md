# Emergency Room Parking — Employee Private Parking Access System

**Concept & Programming:** Dr. Alaa Aqrabawi

نظام ويب بسيط وخاص لإدارة دخول كراج الموظفين باستخدام:

- HTML
- CSS
- JavaScript
- Supabase
- Netlify
- GitHub

بدون:

- Next.js
- React
- npm
- build command
- Terminal
- ملفات معقدة

---

## 1. فكرة النظام

النظام مكوّن من الصفحات التالية فعليًا (حسب الوضع الحالي للريبو):

| الملف | الوظيفة |
|---|---|
| `portal.html` | المدخل العام — تبويبات الموظف/الحارس/الإدارة، وهو المدخل الفعلي الوحيد لتسجيل دخول الإدارة حاليًا |
| `index.html` | شاشة الحارس (Canonical) — QR متغير كل 30 ثانية + بلاغ مخالفة بصورة |
| `verify.html` | صفحة تسجيل الموظف أو التحقق من الدخول |
| `login.html` | **متوقفة فعليًا** — تُعيد التوجيه تلقائيًا إلى `portal.html`؛ استخدمي تبويب الإدارة في `portal.html` |
| `profile.html` | الملف الشخصي للموظف (قراءة فقط) |
| `admin_dashboard.html` | لوحة الإدارة الكاملة |
| `schema.sql` + `schema_patch_*.sql` | تجهيز وتحديث قاعدة بيانات Supabase (راجعي `PRODUCTION_RPC_CANONICAL_MAP.md` قبل أي تشغيل) |
| `netlify.toml` | إعداد Netlify |
| `OPERATIONS_24_7.md` | شروط التشغيل المستمر واختبارات الاعتماد قبل التشغيل الفعلي |
| `ALBASHIR_GATE_24_7_FINAL_SOLUTION_REPORT.md` | تقرير مشاكل وحلول 24/7 حسب آخر مراجعة |
| `qr_load_test_100.js` | سكريبت اختبار ضغط يدوي، موجود في جذر الريبو (لا يوجد مجلد `tests/` منفصل حاليًا) |

> `register.html` غير موجودة بعد كصفحة مستقلة — التسجيل حاليًا جزء من `verify.html`. `guard.html` تقرّر رسميًا عدم إنشائها؛ `index.html` هي الشاشة المعتمدة للحارس (انظر `docs/ALBASHIR_Guard_Specification_v2.1.md`).

---

## 2. طريقة العمل

الموظفون يحصلون على رابط التسجيل عبر واتساب.

الموظف يفتح الرابط ويعبئ:

- الاسم الكامل
- رقم الموظف
- رقم الهاتف
- القسم / الاختصاص

الطلب يظهر في لوحة الأدمن.

الحارس يفتح `index.html` على هاتفه، ويعرض QR للموظفين.

QR:

- يتغير كل 30 ثانية
- ينتهي بعد 30 ثانية
- ينتهي بعد أول استخدام
- يظهر نتيجة الدخول على شاشة الحارس

النتائج:

| النتيجة | المعنى | اللون |
|---|---|---|
| `ALLOWED` | مسموح بالدخول | أخضر |
| `DENIED` | غير مسموح | أحمر |
| `LIMITED` | مسموح جزئيًا | أصفر |
| `PENDING_FIRST_ENTRY` | دخول أول مرة بعد التسجيل | أصفر |

---

## 3. الدخول الأول بعد التسجيل

الموظف الجديد يحصل على دخول أول مرة فقط إذا:

- أدخل الاسم
- أدخل رقم الموظف
- أدخل رقم الهاتف
- أدخل القسم / الاختصاص
- فتح الصفحة من QR صالح وغير مستخدم

هذا الدخول:

- لا يجعله Approved نهائيًا
- يظهر في لوحة الإدارة بوضوح
- يستخدم مرة واحدة فقط
- بعده يبقى الطلب `PENDING`
- لا يستطيع الدخول مرة ثانية إلا بعد موافقة الإدارة

---

## 4. خطوات Supabase

### الخطوة 1 — إنشاء مشروع Supabase

ادخلي إلى Supabase وأنشئي مشروعًا جديدًا.

بعد إنشاء المشروع، ستحتاجين:

```txt
Project URL
Anon / Publishable Key
```

مهم جدًا:

```txt
لا تضعي service_role key في ملفات HTML أبدًا.
استخدمي فقط anon / publishable key.
```

---

### الخطوة 2 — تشغيل schema.sql

افتحي:

```txt
Supabase Dashboard → SQL Editor → New Query
```

انسخي محتوى ملف:

```txt
schema.sql
```

ثم اضغطي:

```txt
Run
```

إذا ظهر تحذير عن Realtime أو publication موجود مسبقًا، غالبًا يمكن تجاهله إذا الجداول انعملت.

---

### الخطوة 3 — إنشاء مستخدم الإدارة

افتحي:

```txt
Authentication → Users
```

ثم أضيفي مستخدمًا جديدًا:

```txt
Email: الإيميل الذي ستدخلين به إلى لوحة الإدارة
Password: كلمة مرور قوية
Auto Confirm: مفعّل إذا ظهر الخيار
```

بعد إنشاء المستخدم:

1. افتحي المستخدم.
2. انسخي `User UID`.

---

### الخطوة 4 — إضافة Super Admin

بعد نسخ `User UID`، افتحي:

```txt
SQL Editor → New Query
```

وشغّلي هذا الكود بعد تبديل القيم:

```sql
insert into public.admin_profiles (
  auth_user_id,
  email,
  full_name,
  role,
  is_active
)
values (
  'PASTE_YOUR_AUTH_USER_UID_HERE',
  'PASTE_YOUR_AUTH_EMAIL_HERE',
  'Dr. Alaa Aqrabawi',
  'SUPER_ADMIN',
  true
)
on conflict (auth_user_id)
do update set
  email = excluded.email,
  full_name = excluded.full_name,
  role = 'SUPER_ADMIN',
  is_active = true;
```

للتأكد:

```sql
select *
from public.admin_profiles;
```

يجب أن يظهر:

```txt
role = SUPER_ADMIN
is_active = true
```

---

## 5. وضع قيم Supabase داخل الملفات

افتحي كل ملف من الملفات التالية:

```txt
index.html
verify.html
login.html
admin_dashboard.html
```

وابحثي عن:

```js
SUPABASE_URL: "https://qinsfvlspdticposbvst.supabase.co",
SUPABASE_ANON_KEY: "sb_publishable_okoDqbwZNNvrCZQ025RkPw_qFXkA7I8",
```

بدّليها بالقيم الحقيقية من Supabase.

مثال:

```js
SUPABASE_URL: "https://xxxxxxxx.supabase.co",
SUPABASE_ANON_KEY: "eyJhbGciOi..."
```

في `index.html` و `verify.html` يوجد أيضًا:

```js
LIVE_SITE_URL: "https://sprightly-donut-6db8c8.netlify.app",
```

بعد نشر الموقع على Netlify، ضعي رابط الموقع النهائي مثل:

```js
LIVE_SITE_URL: "https://sprightly-donut-6db8c8.netlify.app",
```

قبل نشر Netlify يمكن تركها كما هي، وسيحاول الموقع استخدام الرابط الحالي تلقائيًا.

---

## 6. رفع المشروع على GitHub

ارفعي الملفات التالية إلى GitHub في نفس المكان:

```txt
index.html
verify.html
login.html
admin_dashboard.html
schema.sql
README.md
netlify.toml
```

لا تضعيها داخل مجلدات معقدة.

---

## 7. إعداد Netlify

من Netlify:

```txt
Add new site → Import from Git
```

اختاري المستودع من GitHub.

الإعدادات:

```txt
Branch: main
Build command: اتركيه فارغًا
Publish directory: .
Functions directory: اتركيه كما هو أو فارغًا
```

إذا الملفات داخل مجلد وليس في root، ضعي اسم المجلد في Base directory.

لكن الأفضل لهذا المشروع:

```txt
الملفات تكون في root
Publish directory = .
Build command = empty
```

---

## 8. الصفحات بعد النشر

بعد نشر الموقع:

| الصفحة | الرابط |
|---|---|
| شاشة الحارس | `/index.html` |
| تسجيل الموظفين | `/verify.html` |
| دخول الإدارة | `/login.html` |
| لوحة الإدارة | `/admin_dashboard.html` |

مثال:

```txt
https://sprightly-donut-6db8c8.netlify.app/index.html
https://sprightly-donut-6db8c8.netlify.app/verify.html
https://sprightly-donut-6db8c8.netlify.app/login.html
https://sprightly-donut-6db8c8.netlify.app/admin_dashboard.html
```

---

## 9. طريقة الاستخدام اليومية

### الحارس

يفتح:

```txt
index.html
```

ثم يعرض QR للموظف.

الحارس لا يحتاج إلى بحث أو كتابة.

إذا حدثت مخالفة:

1. يضغط تسجيل مخالفة.
2. يلتقط صورة.
3. يضيف رقم الموظف أو ملاحظة إذا عرف.
4. يرسل البلاغ.

---

### الموظف

يفتح رابط QR أو رابط التسجيل.

إذا جديد:

```txt
يعبئ نموذج التسجيل
```

إذا مسجل:

```txt
يدخل رقم الموظف + رقم الهاتف
```

---

### الأدمن

يفتح:

```txt
login.html
```

يسجل الدخول بنفس إيميل وكلمة مرور Supabase Auth.

ثم ينتقل إلى:

```txt
admin_dashboard.html
```

---

## 10. صلاحيات الإدارة

### SUPER_ADMIN

يستطيع:

- الموافقة والرفض
- إضافة مشرفين
- تعطيل مشرفين
- تعديل حدود الاختصاصات
- رؤية البلاغات
- رؤية الإحصائيات
- تصدير CSV
- رؤية Audit

### SUB_ADMIN

يستطيع:

- الموافقة والرفض
- رؤية البلاغات
- رؤية الإحصائيات
- رؤية سجلات الدخول

ولا يستطيع:

- إضافة مشرفين
- تغيير حدود الاختصاصات
- رفع نفسه إلى Super Admin

---

## 11. ملاحظات أمان مهمة

- لا تستخدمي `service_role` داخل أي HTML.
- لا تنشري Database password.
- استخدمي فقط anon / publishable key.
- الصلاحيات محمية بـ RLS و RPC.
- شاشة الحارس بسيطة ومفتوحة وظيفيًا، لذلك لا تشاركي رابطها إلا مع الحارس أو الفريق المسؤول.
- لنسخة أقوى أمنيًا لاحقًا يمكن إضافة تسجيل دخول للحارس أو Edge Function.

---

## 12. إذا ظهرت شاشة بيضاء

المفروض لا تظهر شاشة بيضاء.

إذا ظهر خطأ، افحصي:

1. هل شغّلتِ `schema.sql`؟
2. هل وضعتِ `SUPABASE_URL`؟
3. هل وضعتِ `SUPABASE_ANON_KEY`؟
4. هل أضفتِ Super Admin في `admin_profiles`؟
5. هل دخلتِ من `login.html` بنفس إيميل Auth؟
6. هل Netlify Publish directory = `.`؟

---

## 13. الملفات المطلوبة نهائيًا

```txt
index.html
verify.html
login.html
admin_dashboard.html
schema.sql
README.md
netlify.toml
```



---

## القيم التي تم إدخالها في هذه النسخة

```txt
APP_NAME = Emergency Room Parking
LIVE_SITE_URL = https://sprightly-donut-6db8c8.netlify.app
SUPABASE_URL = https://qinsfvlspdticposbvst.supabase.co
SUPABASE_ANON_KEY = تم إدخاله داخل ملفات HTML
```

ملاحظة: رابط Supabase الذي أعطيته كان يحتوي `/rest/v1/`، وتم تصحيحه داخل الملفات إلى رابط المشروع الأساسي:

```txt
https://qinsfvlspdticposbvst.supabase.co
```


---

## V1.1 — معلومات المستشفى والشعار والصلاحيات

تم اعتماد:

```txt
App Name: Emergency Room Parking
Hospital Arabic: مستشفى الإسعاف والطوارئ / البشير
Hospital English: Al-Bashir Hospital Emergency Department
Logo file: logo.jpeg
Favicon file: favicon.svg
```

### الاختصاصات النهائية

```txt
- جراحة عامة: Max 7 per day
- باطني: Max 7 per day
- ENT: Max 7 per day
- نسائية: Max 7 per day
- مسالك بولية: Max 7 per day
- عيون: Max 7 per day
- جراحة دماغ وأعصاب: Max 7 per day
- تخدير: Max 7 per day
- طب عام: Max 7 per day
- جراحة أوعية دموية: Max 7 per day
- أخرى: Max 7 per day
```

### حسابات الإدارة

لا تُحفظ بيانات حسابات الإدارة الخاصة داخل المستودع العام. أنشئ الحسابات
من Supabase Auth، ثم أضف ملفاتها من لوحة SUPER_ADMIN أو من ملف SQL خاص
لا يُرفع إلى GitHub. ملف setup_sub_admins.sql مستبعد بواسطة .gitignore.

الصلاحيات الافتراضية المقترحة للمشرفين:
- موافقة / رفض طلبات التسجيل
- مراجعة بلاغات الحارس
- رؤية سجلات الدخول والإحصائيات

وتبقى الصلاحيات التالية غير مفعّلة افتراضيًا إلا إذا عدلتيها من صفحة Admins:
- تصدير CSV
- تعديل حدود الاختصاصات اليومية
- رؤية Audit

### صلاحيات المشرفين من صفحة Admins

من صفحة `Admins` يستطيع `SUPER_ADMIN`:

- إضافة مشرف
- تعديل مشرف
- تعطيل مشرف
- حذف مشرف من لوحة الإدارة
- تحديد رقم الهاتف
- تحديد الدور
- تحديد المهام التالية:
  - موافقة / رفض طلبات التسجيل
  - مراجعة بلاغات الحارس
  - رؤية سجلات الدخول والإحصائيات
  - تصدير CSV
  - تعديل حدود الاختصاصات اليومية
  - رؤية Audit

ملاحظة: حذف المشرف من لوحة الإدارة لا يحذف مستخدم Supabase Auth نفسه.

---

## V1.3 — قاعدة QR لكل دخول

تم تثبيت القاعدة التالية داخل الواجهات والتعليمات:

```txt
كل دخول للكراج يجب أن يتم عبر QR مباشر من شاشة الحارس.
هذا ينطبق على:
- الموظفين
- SUB_ADMIN
- SUPER_ADMIN
- Dr. Alaa Aqrabawi
```

صلاحية الإدارة لا تعني دخول الكراج تلقائيًا.

أي أدمن يريد دخول الكراج يجب أن يكون أيضًا موجودًا في `employee_registrations` وحالته `APPROVED`.

الـ QR:
- يتغير كل 30 ثانية
- ينتهي بعد 30 ثانية
- يستخدم مرة واحدة فقط
- تصوير الشاشة لا يعطي صلاحية لاحقة للدخول

---

## V1.4 — صورة واجهة التطبيق

تم اعتماد الصورة الثانية كواجهة مرئية للتطبيق وتمت تسميتها:

```txt
hero.jpeg
```

يجب رفع الملف مع باقي الملفات في نفس مكان صفحات HTML:

```txt
hero.jpeg
logo.jpeg
favicon.svg
index.html
verify.html
login.html
admin_dashboard.html
```

الاستخدام:
- `hero.jpeg` = صورة واجهة / Banner للتطبيق
- `logo.jpeg` = شعار المستشفى داخل البطاقات
- `favicon.svg` = أيقونة المتصفح / الموقع

---

## V1.5 — Offline Gate Mode

تمت إضافة دعم PWA وتشغيل شاشة الحارس من الكاش عند ضعف أو انقطاع الإنترنت:

```txt
service-worker.js
manifest.json
qrcode.min.js
schema_patch_offline_gate_mode.sql
schema_patch_verify_employee_profile.sql
schema_patch_trusted_device_metadata.sql
schema_patch_employee_profiles.sql
```

بعد تشغيل `schema.sql` والباتشات السابقة، شغّل هذا الملف داخل Supabase SQL Editor:

```txt
schema_patch_offline_gate_mode.sql
schema_patch_verify_employee_profile.sql
schema_patch_trusted_device_metadata.sql
schema_patch_employee_profiles.sql
```

ما يضيفه:
- جدول `gate_devices` لمعرفة جهاز الحارس والبوابة وآخر اتصال.
- جدول `offline_access_logs` لحفظ محاولات الدخول التي حدثت أثناء الانقطاع.
- جدول `gate_sync_status` لمعرفة آخر مزامنة وعدد السجلات المعلقة.
- جدول `offline_device_tokens` لربط مزامنة Offline برمز جهاز محلي.
- مزامنة تلقائية للمحاولات المحفوظة عند عودة الإنترنت.
- تخزين محلي عبر IndexedDB باسم `erp_offline_gate_mode`.
- مكتبة QR محلية بدل CDN حتى يبقى QR يعمل بعد أول تحميل ناجح.
- بيانات الجهاز الموثوق: المعرف، النوع، الاسم، آخر نشاط، ووكيل المتصفح، مع حفظ رمز الجهاز كـ hash فقط.
- تسجيل ربط الأجهزة وتغييراتها في `admin_audit_logs`، مع اكتشاف الجهاز الجديد وإلزام التحقق اليدوي قبل ربطه.
- صفحة `profile.html` لعرض ملف الموظف وسجل QR ورفع طلبات تغيير البيانات.
- جدول `employee_data_change_requests` لمراجعة تغييرات الموظفين من الإدارة فقط.

ملاحظة أمان: في هذه النسخة، وضع Offline يسجل المحاولة فقط ولا يعطي نتيجة `ALLOWED` بدون تحقق Online من Supabase.

### ترتيب إعداد قاعدة البيانات لمشروع جديد

شغّل الملفات مرة واحدة في Supabase SQL Editor بهذا الترتيب:

1. `schema.sql`
2. `schema_patch_pgcrypto_schema_fix.sql`
3. `schema_patch_permanent_specialty.sql`
4. `schema_patch_auto_verify.sql`
5. `schema_patch_offline_gate_mode.sql`
6. `schema_patch_verify_employee_profile.sql`
7. `schema_patch_employee_profiles.sql`
8. `schema_patch_trusted_device_registration_flow.sql`
9. `schema_patch_trusted_device_metadata.sql`
10. `schema_patch_production_hardening.sql`
11. `schema_patch_gate_qr_device_auth.sql`


Migration dependencies:

- Run `schema_patch_pgcrypto_schema_fix.sql` before patches that depend on the trusted-device and offline-device hashing functions.
- Include `schema_patch_trusted_device_registration_flow.sql` because it provides the employee trusted-device registration, approval, and pending-to-trusted promotion flow.
- Run `schema_patch_gate_qr_device_auth.sql` last because it overrides the QR runtime with `create_qr_session(device_code, device_token)` and replaces the unsecured QR-generation flow with trusted guard-device authentication.

بعد ذلك أنشئ أول حساب SUPER_ADMIN في Supabase Auth وأضف سجله الإداري
بملف خاص. لا ترفع الملف الذي يحتوي بيانات الحساب إلى GitHub.

### النشر

هذا تطبيق ثابت ويمكن نشره على GitHub Pages أو Netlify. يجب استخدام HTTPS
حتى تعمل الكاميرا وService Worker. حدّث `LIVE_SITE_URL` في `index.html`
إلى رابط النشر النهائي قبل اختبار QR من هاتف آخر.
