# التقرير النهائي للحلول - ALBASHIR Gate 24/7

تاريخ التحديث: 2026-09-28
المجلد الجاهز: `Emergency-Room-Parking-GitHub-Ready-2026-09-28`

## الخلاصة

تم تنفيذ تصليحات P0/P1 الأساسية التي كانت تمنع الاعتماد المبدئي:

- حفظ آخر QR صالح في الذاكرة و`localStorage` مع `token` و`expiresAt`.
- منع استبدال QR صالح برابط عام عند فشل Supabase.
- retry/backoff للـ QR بقيم `2s -> 5s -> 15s -> 30s`.
- منع تداخل طلبات QR عبر `qrRuntime.refreshing`.
- استخدام `expires_in_seconds` القادم من `create_qr_session` في العداد.
- إضافة فحص احتياطي `polling` كل 5 ثوان عند سقوط Realtime.
- إضافة ring-buffer لآخر 50 خطأ في `localStorage`.
- إضافة `pendingCount` ظاهر في صفحة التحقق.
- إضافة `retry_count` محلي لعناصر IndexedDB Offline Queue.
- إضافة `idx_employee_registrations_employee_mobile`.
- إضافة `cleanup_expired_qr_sessions()` ونقل حذف جلسات QR القديمة خارج `create_qr_session`.
- إضافة أعمدة تشخيص `last_qr_at`, `last_scan_at`, `app_version` إلى `gate_devices`.
- عرض بيانات الأجهزة والمزامنة في لوحة الأدمن.
- جعل تثبيت Service Worker لا يفشل بالكامل إذا فشل تخزين ملف واحد.

## P0

### QR Stability

الحالة: **منفذ**

الملفات:

- `index.html`
- `schema.sql`
- `schema_patch_production_hardening.sql`

السلوك الحالي:

- في حال فشل إنشاء QR جديد تبقى الشاشة تعرض آخر QR صالح.
- لا يتم عرض QR خارجي بلا `token` أثناء وجود Supabase.
- آخر QR صالح يحفظ محليا ويسترجع عند فتح الصفحة إذا لم ينته.
- الطلبات المتداخلة ممنوعة، والـ watchdog يحاول الإنعاش عند تأخر آخر نجاح أكثر من 90 ثانية.

### Indexes وQR Cleanup

الحالة: **منفذ**

تمت إضافة:

```sql
create index if not exists idx_employee_registrations_employee_mobile
on public.employee_registrations(employee_id, mobile_number);
```

وتمت إضافة:

```sql
public.cleanup_expired_qr_sessions()
```

ملاحظة تشغيلية: شغل دالة التنظيف عبر Scheduled Function أو Cron في Supabase، مثلا كل 10-30 دقيقة.

### Realtime + سقوط الشبكة

الحالة: **منفذ**

- Realtime يعيد الاشتراك عند الفشل.
- عند عدم استقرار Realtime، يوجد polling احتياطي لصف `guard_screen_status`.
- Offline لا يعطي `ALLOWED` بدون Supabase.
- صفحة التحقق تعرض عدد المحاولات المحفوظة للمزامنة.
- `synced_count` في `sync_offline_access_logs` يحسب الإدخالات الجديدة فقط.

## P1

### Lifecycle

الحالة: **منفذ جزئيا ومناسب للمرحلة الحالية**

- شاشة الحارس تنظف المؤقتات وRealtime عند مغادرة الصفحة.
- صفحة التحقق توقف الكاميرا عند إخفاء الصفحة وتزامن عند العودة.
- بقي اختبار تشغيل 72 ساعة فعلي قبل الاعتماد النهائي.

### Monitoring

الحالة: **منفذ**

- شاشة الحارس تعرض تشخيص QR/Realtime/RPC/Cache.
- الأدمن يعرض أجهزة البوابة، آخر اتصال، آخر QR، آخر Scan، نسخة الكاش، ونسخة التطبيق.
- الأخطاء الأخيرة تحفظ محليا في `erp_gate_error_ring_v1`.

### Cache / Service Worker

الحالة: **منفذ**

- `CACHE_VERSION` موحد على `emergency-room-parking-offline-v14`.
- HTML يعمل network-first.
- الأصول تعمل بتحديث آمن مع fallback.
- التثبيت لا يفشل بالكامل إذا فشل تخزين أصل واحد.

## P2

### Security

الحالة: **محسن**

- سياسة `violation-photos` ضيقت إلى مسار `violations/` وأنواع صور محددة وحجم 5MB.
- واجهة رفع المخالفات تتحقق من النوع والحجم قبل الإرسال.
- `set_guard_status` محمي من الاستخدام المباشر في hardening patch.
- تنبيه الجهاز الجديد موجود في واجهة الموظف.

### Admin Performance

الحالة: **مقبول للـ 400 موظف، ويحتاج تطوير لاحق عند نمو السجلات**

- تم تقليل بعض الجلب عبر حدود `limit`.
- ما زال يوصى لاحقا بإضافة keyset pagination كامل للسجلات الكبيرة عند تضخم البيانات.

## اختبارات تمت محليا

- فحص JavaScript لكل الصفحات الرئيسية: ناجح.
- `node --check service-worker.js`: ناجح.
- `node --check tests/qr_load_test_100.js`: ناجح.
- تحميل الصفحات من السيرفر المحلي `http://127.0.0.1:8010/`: ناجح.

## بوابات القبول قبل التشغيل الفعلي

هذه لا يمكن إثباتها من الفحص السريع فقط، ويجب تنفيذها قبل اعتماد المستشفى:

1. تشغيل شاشة الحارس 72 ساعة بدون QR ميت.
2. اختبار 100 تحقق متزامن والتأكد أن `p95 < 2s`.
3. فصل الإنترنت 10 دقائق ثم إعادته والتأكد من مزامنة السجلات دون تكرار.
4. إعادة استخدام QR مستهلك يجب أن تعطي `DENIED`.
5. فتح الأدمن بدون دور يجب أن يعيد المستخدم إلى `portal.html`.
6. رفع نسخة جديدة على Netlify ثم reload للتأكد من عدم بقاء نسخة قديمة.

## ترتيب SQL المطلوب

عند تجهيز Supabase، شغل الملفات بهذا الترتيب:

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

بعدها أضف جدولة دورية لدالة:

```sql
select public.cleanup_expired_qr_sessions();
```
