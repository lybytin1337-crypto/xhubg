const TelegramBot = require('node-telegram-bot-api');
const fs = require('fs');

// ========================
//  НАСТРОЙКИ
// ========================
const TOKEN = process.env.BOT_TOKEN || '8764368268:AAF_cyWYFYvaqBPCZzJl3eFyKePk64lbwWo';
const XAI_API_KEY = process.env.XAI_API_KEY || 'xai-gBEhAOihQBdjkhnNqWC7TSLRqwXvsT8rZO5bPKxXYAMGhpA6LKkVpggZXn5SgjQ7vU85feZEGVuRulIZ';
const DATA_FILE = './chat_memory.json';

const REPLY_CHANCE = 0.1;
const TRIGGER_WORDS = ['грок', 'друг эга', 'друг'];
const MAX_STYLE_MESSAGES = 200;
const MAX_CONTEXT = 20;

// ========================
//  ПАМЯТЬ
// ========================
let memory = {
  styleMessages: [],
  conversations: {},
};

if (fs.existsSync(DATA_FILE)) {
  try {
    memory = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    console.log(`📂 Загружена память: ${memory.styleMessages.length} примеров стиля`);
  } catch (e) {
    console.log('⚠️ Не удалось загрузить память, начинаю заново');
  }
}

function saveMemory() {
  fs.writeFileSync(DATA_FILE, JSON.stringify(memory, null, 2));
}

// ========================
//  ИНИЦИАЛИЗАЦИЯ
// ========================
const bot = new TelegramBot(TOKEN, { polling: true });
console.log('🤖 Бот запущен!');

// ========================
//  СБОР СТИЛЯ
// ========================
function addStyleMessage(msg) {
  if (!msg.text || msg.text.startsWith('/')) return;
  if (msg.from.is_bot) return;

  memory.styleMessages.push({
    user: msg.from.first_name || 'Аноним',
    text: msg.text,
    timestamp: Date.now(),
  });

  if (memory.styleMessages.length > MAX_STYLE_MESSAGES) {
    memory.styleMessages = memory.styleMessages.slice(-MAX_STYLE_MESSAGES);
  }

  saveMemory();
}

function buildStylePrompt() {
  if (memory.styleMessages.length === 0) {
    return 'Общайся как обычный человек в чате — непринуждённо, с юмором.';
  }

  const examples = memory.styleMessages
    .slice(-50)
    .map(m => `${m.user}: ${m.text}`)
    .join('\n');

  return `Ты — часть чата. Изучи манеру общения людей и копируй их стиль:
  
ПРИМЕРЫ СООБЩЕНИЙ ИЗ ЧАТА:
${examples}

Твои правила:
- Говори так же, как говорят люди в этом чате
- Используй похожие слова, сленг, сокращения, эмодзи если они есть
- Будь кратким — отвечай 1-3 предложениями как в чате
- Иногда шути как шутят в этом чате
- НЕ говори что ты бот или ИИ
- Отвечай на русском если в чате говорят по-русски`;
}

// ========================
//  ВЫЗОВ XAI API
// ========================
async function callGrok(messages) {
  const response = await fetch('https://api.x.ai/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${XAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'grok-3-mini',
      messages: messages,
      max_tokens: 500,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`xAI API error: ${response.status} ${err}`);
  }

  const data = await response.json();
  return data.choices[0].message.content;
}

// ========================
//  ГЕНЕРАЦИЯ ОТВЕТА
// ========================
async function generateTextReply(chatId, userMessage) {
  if (!memory.conversations[chatId]) {
    memory.conversations[chatId] = [];
  }

  const ctx = memory.conversations[chatId];
  ctx.push({ role: 'user', content: userMessage });

  if (ctx.length > MAX_CONTEXT) {
    memory.conversations[chatId] = ctx.slice(-MAX_CONTEXT);
  }

  const systemPrompt = buildStylePrompt();

  const messages = [
    { role: 'system', content: systemPrompt },
    ...memory.conversations[chatId],
  ];

  const reply = await callGrok(messages);

  memory.conversations[chatId].push({
    role: 'assistant',
    content: reply,
  });

  saveMemory();
  return reply;
}

async function generateImagePrompt(context) {
  const messages = [
    { role: 'system', content: 'Ты помогаешь генерировать промпты для изображений.' },
    {
      role: 'user',
      content: `На основе этого контекста чата придумай короткий промпт для генерации картинки (на английском, 10-20 слов), которая была бы уместна в этом разговоре. Верни ТОЛЬКО промпт, без объяснений.\n\nКонтекст: ${context}`,
    },
  ];
  return await callGrok(messages);
}

// ========================
//  ОБРАБОТКА СООБЩЕНИЙ
// ========================
bot.on('message', async (msg) => {
  const chatId = msg.chat.id;
  const text = msg.text || '';

  if (text === '/start') {
    bot.sendMessage(chatId, '👋 Привет! Я учусь общаться как вы. Просто общайтесь в чате — я наблюдаю и иногда буду вступать в разговор.');
    return;
  }

  if (text === '/stats') {
    bot.sendMessage(chatId, `📊 Статистика:\n• Собрано примеров стиля: ${memory.styleMessages.length}\n• Чатов в памяти: ${Object.keys(memory.conversations).length}`);
    return;
  }

  if (text === '/forget') {
    memory.conversations[chatId] = [];
    saveMemory();
    bot.sendMessage(chatId, '🧹 Контекст разговора очищен!');
    return;
  }

  if (msg.from.is_bot) return;

  if (text && !text.startsWith('/')) {
    addStyleMessage(msg);
  }

  const textLower = text.toLowerCase();
  const isReplyToBot = !!msg.reply_to_message?.from?.is_bot;
  const isPrivate = msg.chat.type === 'private';
  const isMentionedByUsername = textLower.includes('@');
  const isCalledByName = TRIGGER_WORDS.some(word => textLower.includes(word));

  const isDirectMention = isReplyToBot || isPrivate || isMentionedByUsername || isCalledByName;
  const shouldReply = isDirectMention || Math.random() < REPLY_CHANCE;

  if (!shouldReply) return;
  if (!text || text.startsWith('/')) return;

  const imageKeywords = ['нарисуй', 'нарисуйте', 'сгенерируй', 'сгенерируйте', 'покажи картинку', 'создай картинку', 'draw', 'generate image', 'картинку', 'изображение'];
  const wantsImage = imageKeywords.some(kw => textLower.includes(kw));

  try {
    if (wantsImage) {
      try {
        bot.sendChatAction(chatId, 'upload_photo');
        const imagePrompt = await generateImagePrompt(text);
        console.log(`🎨 Промпт для картинки: ${imagePrompt}`);

        const imgResponse = await fetch('https://api.x.ai/v1/images/generations', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${XAI_API_KEY}`,
          },
          body: JSON.stringify({
            model: 'grok-2-image',
            prompt: imagePrompt,
            n: 1,
          }),
        });

        if (imgResponse.ok) {
          const imgData = await imgResponse.json();
          const url = imgData.data?.[0]?.url;
          if (url) {
            await bot.sendPhoto(chatId, url, { reply_to_message_id: msg.message_id });
            return;
          }
        }
      } catch (imgErr) {
        console.log('⚠️ Ошибка генерации картинки, отвечаю текстом:', imgErr.message);
      }
    }

    bot.sendChatAction(chatId, 'typing');
    const reply = await generateTextReply(chatId, text);
    console.log(`💬 [${chatId}] ${msg.from.first_name}: ${text}`);
    console.log(`🤖 Ответ: ${reply}`);

    await bot.sendMessage(chatId, reply, {
      reply_to_message_id: isDirectMention ? msg.message_id : undefined,
    });
  } catch (err) {
    console.error('❌ Ошибка:', err.message);
  }
});

// ========================
//  GRACEFUL SHUTDOWN
// ========================
process.on('SIGINT', () => {
  saveMemory();
  console.log('\n💾 Память сохранена. Бот остановлен.');
  process.exit(0);
});

console.log('✅ Бот готов к работе!');
