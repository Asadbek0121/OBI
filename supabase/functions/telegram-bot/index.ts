// @ts-ignore
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7"

// @ts-ignore
const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") || "";
// @ts-ignore
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "";
// @ts-ignore
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

serve(async (req: Request) => {
  try {
    const update = await req.json();
    
    if (update.message) {
      await handleMessage(update.message);
    } else if (update.callback_query) {
      await handleCallback(update.callback_query);
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error(err);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});

async function handleMessage(msg: any) {
  const chatId = msg.chat.id.toString();
  const text = msg.text || "";

  // 1. Get User
  const { data: users } = await supabase
    .from("telegram_users")
    .select("*")
    .eq("chat_id", chatId)
    .limit(1);
    
  const user = users?.[0] || null;

  if (!user) {
    // Register pending
    await supabase.from("telegram_users").insert({
      chat_id: chatId,
      name: msg.from.first_name || "User",
      role: "pending",
      created_at: new Date().toISOString()
    });
    
    await sendMessage(chatId, "⏳ *Arizangiz qabul qilindi.* \n\nSiz tizimda ro'yxatdan o'tmagansiz. Admin ruxsatini kuting.");
    return;
  }

  if (user.role === 'pending') {
    await sendMessage(chatId, "⏳ *Ruxsat kutilmoqda...*");
    return;
  }

  // 2. Handle Commands
  if (text === "/start" || text.includes("Asosiy Menyu")) {
    await sendMainMenu(chatId, "👋 Xush kelibsiz!", user.role);
    return;
  }

  if (text.includes("Bugungi Holat")) {
    await handleTodayStats(chatId);
  } else if (text.includes("Umumiy Hisobot")) {
    await handleTotalStats(chatId);
  } else if (text.includes("Kam Qolganlar")) {
    await handleLowStock(chatId);
  } else if (text.includes("Jihozlar")) {
    await handleEquipments(chatId);
  } else if (text.includes("Yangilash")) {
    await sendMainMenu(chatId, "🔄 Ma'lumotlar yangilandi", user.role);
  } else {
    if (text.includes("AI") || text.includes("Qidirish") || text.includes("Harakatlar") || text.includes("Excel") || text.includes("Foto Buyurtma") || text.includes("Buyurtma") || text.includes("QR Skanerlash")) {
        await sendMessage(chatId, "⏳ *Tez orada...*\n\nBu yangi funksiyalar ayni paytda Cloud (Bulutli) bot uchun moslashtirilmoqda. Iltimos biroz kuting!");
    }
  }
}

async function handleLowStock(chatId: string) {
    const { data: products } = await supabase.from("products").select("name, stock, unit").lte("stock", 5).limit(20);
    if (!products || products.length === 0) {
        await sendMessage(chatId, "✅ Kam qolgan mahsulotlar yo'q!");
        return;
    }
    const msg = products.map((p: any) => `⚠️ ${p.name}: *${p.stock} ${p.unit}*`).join('\n');
    await sendMessage(chatId, `📉 *KAM QOLGAN MAHSULOTLAR*\n\n${msg}`);
}

async function handleEquipments(chatId: string) {
    const { data: equipments } = await supabase.from("equipments").select("name, condition").limit(20);
    if (!equipments || equipments.length === 0) {
        await sendMessage(chatId, "🖥 Jihozlar topilmadi.");
        return;
    }
    const msg = equipments.map((e: any) => `🔹 ${e.name} (${e.condition})`).join('\n');
    await sendMessage(chatId, `🖥 *JIHOZLAR RO'YXATI*\n\n${msg}`);
}

async function handleTodayStats(chatId: string) {
    const today = new Date().toISOString().split('T')[0];
    
    const { data: stockIn } = await supabase.from("stock_in").select("quantity").gte("date_time", today);
    const { data: stockOut } = await supabase.from("stock_out").select("quantity").gte("date_time", today);

    const inQty = stockIn?.reduce((sum: number, item: any) => sum + (item.quantity || 0), 0) || 0;
    const outQty = stockOut?.reduce((sum: number, item: any) => sum + (item.quantity || 0), 0) || 0;

    await sendMessage(chatId, `📊 *BUGUNGI HOLAT*\n\n📥 Kirim: *${inQty}*\n📤 Chiqim: *${outQty}*`);
}

async function handleTotalStats(chatId: string) {
    const { data: products } = await supabase.from("products").select("id");
    const count = products?.length || 0;
    await sendMessage(chatId, `💰 *UMUMIY HISOBOT*\n\n📦 Mahsulotlar turi: *${count} ta*`);
}

async function sendMainMenu(chatId: string, text: string, role: string) {
  let keyboard = [];
  if (role === 'admin') {
    keyboard = [
      [{ text: "📊 Bugungi Holat" }, { text: "💰 Umumiy Hisobot" }],
      [{ text: "🧠 AI Analizator" }],
      [{ text: "⚠️ Kam Qolganlar" }, { text: "🖥 Jihozlar" }],
      [{ text: "🔄 Oxirgi Harakatlar" }, { text: "🔎 Mahsulot Qidirish" }],
      [{ text: "📥 Excel Hisobot" }, { text: "🔄 Yangilash" }]
    ];
  } else if (role === 'branch') {
    keyboard = [
      [{ text: "📷 Foto Buyurtma" }, { text: "📷 QR Skanerlash" }],
      [{ text: "📝 Buyurtma Holati" }],
      [{ text: "🔄 Yangilash" }]
    ];
  } else {
    keyboard = [
      [{ text: "ℹ️ Ma'lumot" }, { text: "🔄 Yangilash" }]
    ];
  }

  await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text: text,
      parse_mode: "Markdown",
      reply_markup: { keyboard, resize_keyboard: true }
    })
  });
}

async function handleCallback(cb: any) {
  // Logic for callbacks...
}

async function sendMessage(chatId: string, text: string) {
  await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text: text,
      parse_mode: "Markdown"
    })
  });
}
