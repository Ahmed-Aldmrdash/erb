-- ============================================================================
-- مسح كل البيانات التجريبية من السيرفر
--
-- بيمسح: العملاء والفلاحين والتجار، الأصناف، الفواتير، المحاصيل والتوريدات،
-- الخزن والفلوس، المخازن، التذكرة، إعدادات المؤسسة، والموبايلات المتسجلة،
-- وحسابات الإيميل بتاعة النسخة الأولى.
-- مش بيمسح: أسماء المستخدمين وكلمات المرور بتاعة المعرض والتجارة والإدارة
-- (شوف آخر الملف لو عايز تمسحهم كمان).
--
-- بعد ما تشغّله: كل موبايل هيسجل دخول تاني، وأول ما يتصل بالسيرفر هيمسح
-- البيانات القديمة اللي عليه لوحده. المحاصيل الأساسية والخزنة والمخزن
-- الرئيسي بيتعملوا تاني أوتوماتيك.
--
-- الطريقة: Supabase ← SQL Editor ← New query، الصق الملف كله ودوس Run.
-- شغّل ملف schema.sql الجديد الأول لو لسه ماشغلتوش.
-- ============================================================================

do $$
begin
  if to_regclass('public.erp_state') is null then
    raise exception 'شغّل ملف supabase/schema.sql الجديد الأول، وبعدين الملف ده';
  end if;
end $$;

begin;

-- 1) كل البيانات في القسمين
truncate table
  public.app_settings,
  public.parties,
  public.warehouses,
  public.cash_boxes,
  public.crops,
  public.products,
  public.crop_trades,
  public.invoices,
  public.invoice_lines,
  public.installments,
  public.vouchers,
  public.stock_moves,
  public.notes;

-- 2) الدخول والموبايلات: كل موبايل يسجل دخول من جديد
truncate table public.sessions, public.login_attempts, public.devices;

-- 3) نقول للموبايلات إن البيانات اتمسحت
update public.erp_state set reset_id = gen_random_uuid()::text, reset_at = now() where id = 1;

-- 4) حسابات الإيميل بتاعة النسخة الأولى (الأبلكيشن مابقاش يستخدمها)
do $$
begin
  if to_regclass('auth.users') is not null then
    delete from auth.users;
  end if;
end $$;

commit;

-- ----------------------------------------------------------------------------
-- (اختياري) لو عايز كمان تمسح أسماء المستخدمين وكلمات المرور وتعملهم من الأول
-- من الأبلكيشن: شيل علامتين الشرطة "--" من أول السطر اللي تحت وشغّله لوحده.
-- truncate table public.departments;
