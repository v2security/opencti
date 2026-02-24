// FORK: Chatbot proxy rewritten to call Claude (Anthropic) API directly
// instead of proxying to Filigran XTM One Flowise service.
import type Express from 'express';
import nconf from 'nconf';
import { createAuthenticatedContext } from './httpAuthenticatedContext';
import { logApp } from '../config/conf';
import { setCookieError } from './httpUtils';

// ---------------------------------------------------------------------------
// Configuration – set via env vars:
//   CHATBOT__API_KEY   (required) – your Anthropic API key
//   CHATBOT__MODEL     (optional) – defaults to claude-sonnet-4-20250514
//   CHATBOT__MAX_TOKENS (optional) – defaults to 4096
// ---------------------------------------------------------------------------
const CHATBOT_API_KEY: string = nconf.get('chatbot:api_key') ?? '';
const CHATBOT_MODEL: string = nconf.get('chatbot:model') ?? 'claude-sonnet-4-5-20250929';
const CHATBOT_MAX_TOKENS: number = Number(nconf.get('chatbot:max_tokens') ?? 4096);
const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';

const SYSTEM_PROMPT = `You are Ariane, an expert AI assistant specialized in Cyber Threat Intelligence (CTI).
You run inside an OpenCTI platform instance. Your purpose is to help analysts with:
- Understanding threat actors, malware, campaigns, and attack patterns
- Interpreting STIX objects and relationships
- Writing and reviewing CTI reports
- Querying the platform and explaining results
- General cybersecurity questions

Be concise, precise, and professional. Use Markdown for formatting when helpful.
When you don't know something, say so rather than guessing.`;

// Simple in-memory conversation history keyed by chatId (cleared on restart)
const conversationHistory = new Map<string, Array<{ role: string; content: string }>>();
const MAX_HISTORY_PER_CHAT = 40; // keep last N messages per chat
const MAX_CHATS = 500; // evict oldest chats when exceeded

function getOrCreateHistory(chatId: string): Array<{ role: string; content: string }> {
  if (!conversationHistory.has(chatId)) {
    // Evict oldest if at capacity
    if (conversationHistory.size >= MAX_CHATS) {
      const oldest = conversationHistory.keys().next().value;
      if (oldest) conversationHistory.delete(oldest);
    }
    conversationHistory.set(chatId, []);
  }
  return conversationHistory.get(chatId)!;
}

// ---------------------------------------------------------------------------
// GET /chatbot – health check expected by @filigran/chatbot component
// ---------------------------------------------------------------------------
export const getChatbotHealthCheck = async (_req: Express.Request, res: Express.Response) => {
  if (!CHATBOT_API_KEY) {
    res.status(503).json({ isStreaming: false, error: 'CHATBOT__API_KEY is not configured' });
    return;
  }
  res.json({ isStreaming: true });
};

// ---------------------------------------------------------------------------
// POST /chatbot – streaming chat via Claude API
// ---------------------------------------------------------------------------
export const getChatbotProxy = async (req: Express.Request, res: Express.Response) => {
  try {
    // Authenticate the request
    const context = await createAuthenticatedContext(req, res, 'chatbot');
    if (!context.user) {
      res.sendStatus(403);
      return;
    }

    if (!CHATBOT_API_KEY) {
      res.status(400).json({ error: 'Chatbot is not configured. Set CHATBOT__API_KEY environment variable.' });
      return;
    }

    if (!req.body?.question) {
      res.status(400).json({ error: 'Chatbot request body is missing or has no question' });
      return;
    }

    const { question, chatId: clientChatId } = req.body;
    const chatId = clientChatId || 'default';

    // Maintain conversation history
    const history = getOrCreateHistory(chatId);
    history.push({ role: 'user', content: question });

    // Trim to max history length
    while (history.length > MAX_HISTORY_PER_CHAT) {
      history.shift();
    }

    // Build Claude API request
    const claudeBody = {
      model: CHATBOT_MODEL,
      max_tokens: CHATBOT_MAX_TOKENS,
      stream: true,
      system: SYSTEM_PROMPT,
      messages: history.map((m) => ({ role: m.role as 'user' | 'assistant', content: m.content })),
    };

    // Call Anthropic Messages API with streaming
    const response = await fetch(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': CHATBOT_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(claudeBody),
    });

    if (!response.ok) {
      const errText = await response.text();
      logApp.error('Claude API error', { status: response.status, body: errText });
      res.status(502).json({ error: `Claude API returned ${response.status}` });
      return;
    }

    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    // Send start event (tells chatbot component to create an empty bot message)
    res.write(`data: ${JSON.stringify({ event: 'start' })}\n\n`);

    // Stream Claude response and translate to chatbot SSE format
    const reader = response.body?.getReader();
    if (!reader) {
      res.write(`data: ${JSON.stringify({ event: 'error', data: 'No response stream' })}\n\n`);
      res.write(`data: ${JSON.stringify({ event: 'end' })}\n\n`);
      res.end();
      return;
    }

    const decoder = new TextDecoder();
    let fullResponse = '';
    let buffer = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        // Process complete SSE lines from Claude
        const lines = buffer.split('\n');
        buffer = lines.pop() || ''; // keep incomplete line in buffer

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const data = line.slice(6).trim();
          if (!data || data === '[DONE]') continue;

          try {
            const parsed = JSON.parse(data);

            if (parsed.type === 'content_block_delta' && parsed.delta?.type === 'text_delta') {
              const text = parsed.delta.text;
              fullResponse += text;
              // Forward as token event
              res.write(`data: ${JSON.stringify({ event: 'token', data: text })}\n\n`);
            }
            // We ignore other Claude event types (message_start, content_block_start, etc.)
          } catch {
            // Skip malformed JSON lines
          }
        }
      }
    } catch (streamErr) {
      logApp.error('Stream read error from Claude', { cause: streamErr });
    }

    // Save assistant response to history
    if (fullResponse) {
      history.push({ role: 'assistant', content: fullResponse });
    }

    // Send metadata + end events
    res.write(`data: ${JSON.stringify({ event: 'metadata', data: { chatId } })}\n\n`);
    res.write(`data: ${JSON.stringify({ event: 'end' })}\n\n`);
    res.end();

    req.on('close', () => {
      reader.cancel().catch(() => {});
    });
  } catch (e: unknown) {
    logApp.error('Error in chatbot proxy', { cause: e });
    const { message } = e as Error;

    if (!res.headersSent) {
      res.status(503).send({ status: 503, error: message });
    } else {
      // Already streaming — send error event and close
      try {
        res.write(`data: ${JSON.stringify({ event: 'error', data: message })}\n\n`);
        res.write(`data: ${JSON.stringify({ event: 'end' })}\n\n`);
      } catch { /* response already closed */ }
      res.end();
    }
    setCookieError(res, message);
  }
};
