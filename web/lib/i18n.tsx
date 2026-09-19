"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";

export type Lang = "en" | "ar";

const en = {
  appName: "Wholesale Orders",
  catalog: "Catalog",
  orders: "Orders",
  cart: "Cart",
  signIn: "Sign in",
  signOut: "Sign out",
  phone: "Phone",
  password: "Password",
  newPassword: "New password",
  setPassword: "Set password",
  welcome: "Welcome",
  welcomeBody:
    "Your invite link is confirmed. Set your password to start ordering.",
  linkExpired: "Link expired — ask the admin for a new one.",
  noAccount: "No account for this phone — ask the admin for an invite.",
  notCustomer: "This login is not a customer account.",
  wrongPassword: "Wrong phone or password.",
  needSignIn: "Sign in to view this page.",
  search: "Search products…",
  noProducts: "No products yet.",
  sizes: "Sizes",
  sizeless: "One size",
  qty: "Qty",
  add: "Add",
  cartEmpty: "Your cart is empty.",
  previewOrder: "Preview order",
  close: "Close",
  decrease: "Decrease",
  increase: "Increase",
  item: "Item",
  submitOrder: "Submit order",
  submitting: "Submitting…",
  orderPlaced: "Order placed.",
  statusPending: "Pending",
  statusCompleted: "Completed",
  editOrder: "Edit",
  doneEditing: "Done",
  saveChanges: "Save changes",
  saving: "Saving…",
  remove: "Remove",
  deleteOrder: "Delete order",
  confirmDelete: "Confirm delete",
  deleting: "Deleting…",
  orderDetail: "Order",
  orderLines: "Lines",
  placedOn: "Placed",
  linesCount: "lines",
  emptyOrders: "No orders yet — place your first one from the catalog.",
  offline: "No connection — check your network and retry.",
  retry: "Retry",
  loading: "Loading…",
  missingConfig: "Server is not configured — set the Supabase env vars.",
  unknownError: "Something went wrong — try again.",
};

export type Strings = typeof en;

const ar: Strings = {
  appName: "طلبات الجملة",
  catalog: "المنتجات",
  orders: "الطلبات",
  cart: "السلة",
  signIn: "تسجيل الدخول",
  signOut: "تسجيل الخروج",
  phone: "رقم الهاتف",
  password: "كلمة المرور",
  newPassword: "كلمة مرور جديدة",
  setPassword: "تعيين كلمة المرور",
  welcome: "مرحباً بك",
  welcomeBody: "تم تأكيد رابط الدعوة. عيّن كلمة المرور لبدء تقديم الطلبات.",
  linkExpired: "انتهت صلاحية الرابط — اطلب رابطاً جديداً من المدير.",
  noAccount: "لا يوجد حساب لهذا الرقم — اطلب دعوة من المدير.",
  notCustomer: "هذا الحساب ليس حساب عميل.",
  wrongPassword: "الرقم أو كلمة المرور غير صحيحة.",
  needSignIn: "سجّل الدخول لعرض هذه الصفحة.",
  search: "ابحث في المنتجات…",
  noProducts: "لا توجد منتجات بعد.",
  sizes: "المقاسات",
  sizeless: "مقاس واحد",
  qty: "الكمية",
  add: "أضف",
  cartEmpty: "سلتك فارغة.",
  previewOrder: "معاينة الطلب",
  close: "إغلاق",
  decrease: "تقليل",
  increase: "زيادة",
  item: "الصنف",
  submitOrder: "تأكيد الطلب",
  submitting: "جارٍ الإرسال…",
  orderPlaced: "تم إرسال الطلب.",
  statusPending: "قيد الانتظار",
  statusCompleted: "مكتمل",
  editOrder: "تعديل",
  doneEditing: "تم",
  saveChanges: "حفظ التغييرات",
  saving: "جارٍ الحفظ…",
  remove: "إزالة",
  deleteOrder: "حذف الطلب",
  confirmDelete: "تأكيد الحذف",
  deleting: "جارٍ الحذف…",
  orderDetail: "طلب",
  orderLines: "الأصناف",
  placedOn: "بتاريخ",
  linesCount: "أصناف",
  emptyOrders: "لا توجد طلبات بعد — قدّم طلبك الأول من المنتجات.",
  offline: "لا يوجد اتصال — تحقق من الشبكة وحاول مجدداً.",
  retry: "إعادة المحاولة",
  loading: "جارٍ التحميل…",
  missingConfig: "الخادم غير مُعد — اضبط متغيرات Supabase.",
  unknownError: "حدث خطأ ما — حاول مجدداً.",
};

const dicts: Record<Lang, Strings> = { en, ar };

interface I18n {
  lang: Lang;
  t: Strings;
  toggle: () => void;
}

const Ctx = createContext<I18n>({ lang: "en", t: en, toggle: () => { } });

function readCookie(): Lang {
  if (typeof document === "undefined") return "en";
  return document.cookie.includes("lang=ar") ? "ar" : "en";
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLang] = useState<Lang>("en");
  // Mount-time hydration from cookie (document is SSR-unsafe during render).
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setLang(readCookie()), []);
  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === "ar" ? "rtl" : "ltr";
    document.cookie = `lang=${lang}; path=/; max-age=31536000`;
  }, [lang]);
  const toggle = useCallback(
    () => setLang((l) => (l === "en" ? "ar" : "en")),
    [],
  );
  return (
    <Ctx.Provider value={{ lang, t: dicts[lang], toggle }}>
      {children}
    </Ctx.Provider>
  );
}

export function useI18n(): I18n {
  return useContext(Ctx);
}
