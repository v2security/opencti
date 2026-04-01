import type Express from 'express';
import nconf from 'nconf';
import { createAuthenticatedContext } from './httpAuthenticatedContext';
import { logApp } from '../config/conf';
import { setCookieError } from './httpUtils';

type ChatHistoryMessage = {
  role: 'user' | 'assistant';
  content: string;
};

const CHATBOT_ENABLED: boolean = nconf.get('chatbot:enabled') ?? true;
const CHATBOT_TYPE: string = (nconf.get('chatbot:type') ?? 'vllm').toLowerCase();
const CHATBOT_API_KEY: string = nconf.get('chatbot:token') ?? '';
const CHATBOT_MODEL: string = nconf.get('chatbot:model') ?? 'Qwen/Qwen2.5-32B-Instruct';
const AI_MODEL: string = nconf.get('ai:model') ?? '';
const CHATBOT_MAX_TOKENS: number = Number(nconf.get('chatbot:max_tokens') ?? 4096);
const OPENAI_COMPATIBLE_DEFAULT_API_KEY = 'dummy';
const SUPPORTED_CHATBOT_TYPES = new Set(['openai', 'vllm']);

const RAW_CHATBOT_ENDPOINT: string = nconf.get('chatbot:endpoint') ?? 'http://localhost:8000/v1';
const NORMALIZED_CHATBOT_ENDPOINT = RAW_CHATBOT_ENDPOINT.replace(/\/+$/, '');
const OPENAI_BASE_URL = NORMALIZED_CHATBOT_ENDPOINT.endsWith('/v1')
  ? NORMALIZED_CHATBOT_ENDPOINT
  : `${NORMALIZED_CHATBOT_ENDPOINT}/v1`;

const OPENAI_CHAT_COMPLETIONS_URL = `${OPENAI_BASE_URL}/chat/completions`;
const CHATBOT_API_KEY_HEADER = CHATBOT_API_KEY || OPENAI_COMPATIBLE_DEFAULT_API_KEY;
const OPENAI_MODELS_URL = `${OPENAI_BASE_URL}/models`;

let resolvedChatbotModel: string | null = null;
let resolvingChatbotModelPromise: Promise<string> | null = null;

const getChatbotConfigurationError = () => {
  if (!CHATBOT_ENABLED) {
    return 'Chatbot is disabled by configuration.';
  }
  if (!SUPPORTED_CHATBOT_TYPES.has(CHATBOT_TYPE)) {
    return `Unsupported chatbot type "${CHATBOT_TYPE}". Supported types: openai, vllm.`;
  }
  return null;
};

export const XTM_ONE_CHATBOT_URL = OPENAI_BASE_URL;

const SYSTEM_PROMPT = `You are V2-AI, an expert AI assistant specialized in Cyber Threat Intelligence (CTI).
You run inside an OpenCTI platform instance. Your purpose is to help analysts with:
- Understanding threat actors, malware, campaigns, and attack patterns
- Interpreting STIX objects and relationships
- Writing and reviewing CTI reports
- Querying the platform and explaining results
- General cybersecurity questions

Be concise, precise, and professional. Use Markdown for formatting when helpful.
When you don't know something, say so rather than guessing.`;

// Conversation state stays in memory only and is reset when the process restarts.
const conversationHistory = new Map<string, ChatHistoryMessage[]>();
const MAX_HISTORY_PER_CHAT = 40;
const MAX_CHATS = 500;

const getPreferredChatbotModels = () => {
  return [CHATBOT_MODEL, AI_MODEL].filter((model): model is string => typeof model === 'string' && model.trim().length > 0);
};

const fetchAvailableChatbotModels = async () => {
  const response = await fetch(OPENAI_MODELS_URL, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${CHATBOT_API_KEY_HEADER}`,
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Model discovery failed with status ${response.status}: ${body}`);
  }

  const payload = await response.json() as { data?: Array<{ id?: unknown }> };
  return Array.isArray(payload?.data)
    ? payload.data
      .map((entry) => (typeof entry?.id === 'string' ? entry.id : null))
      .filter((modelId: string | null): modelId is string => Boolean(modelId))
    : [];
};

const resolveChatbotModel = async (forceRefresh = false) => {
  const configuredModels = getPreferredChatbotModels();
  const fallbackModel = configuredModels[0] ?? CHATBOT_MODEL;

  if (!forceRefresh && resolvedChatbotModel) {
    return resolvedChatbotModel;
  }

  if (!forceRefresh && resolvingChatbotModelPromise) {
    return resolvingChatbotModelPromise;
  }

  const resolvePromise = (async () => {
    try {
      const availableModels = await fetchAvailableChatbotModels();
      if (availableModels.length === 0) {
        return fallbackModel;
      }

      const matchedModel = configuredModels.find((model) => availableModels.includes(model));
      if (matchedModel) {
        return matchedModel;
      }

      const selectedModel = availableModels[0];
      logApp.warn('Configured chatbot model is not served by the OpenAI-compatible endpoint, falling back to an available model', {
        configuredModel: CHATBOT_MODEL,
        aiModel: AI_MODEL,
        endpoint: OPENAI_BASE_URL,
        selectedModel,
      });
      return selectedModel;
    } catch (cause) {
      logApp.warn('Unable to discover chatbot models from the OpenAI-compatible endpoint, using configured model', {
        cause,
        endpoint: OPENAI_BASE_URL,
        fallbackModel,
      });
      return fallbackModel;
    } finally {
      resolvingChatbotModelPromise = null;
    }
  })();

  resolvingChatbotModelPromise = resolvePromise;
  resolvedChatbotModel = await resolvePromise;
  return resolvedChatbotModel;
};

const executeChatbotRequest = async (body: Record<string, unknown>) => {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${CHATBOT_API_KEY_HEADER}`,
  };

  return fetch(OPENAI_CHAT_COMPLETIONS_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
};

const trimHistory = (history: ChatHistoryMessage[]) => {
  while (history.length > MAX_HISTORY_PER_CHAT) {
    history.shift();
  }
};

const writeSseEvent = (res: Express.Response, event: string, data?: unknown) => {
  const payload = data === undefined ? { event } : { event, data };
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
};

function getOrCreateHistory(chatId: string): ChatHistoryMessage[] {
  if (!conversationHistory.has(chatId)) {
    if (conversationHistory.size >= MAX_CHATS) {
      const oldest = conversationHistory.keys().next().value;
      if (oldest) conversationHistory.delete(oldest);
    }
    conversationHistory.set(chatId, []);
  }
  return conversationHistory.get(chatId)!;
}

export const getChatbotHealthCheck = async (_req: Express.Request, res: Express.Response) => {
  const configurationError = getChatbotConfigurationError();
  if (configurationError) {
    res.status(503).json({ isStreaming: false, error: configurationError });
    return;
  }

  const model = await resolveChatbotModel();

  res.json({
    isStreaming: true,
    endpoint: OPENAI_BASE_URL,
    model,
  });
};

export const getChatbotProxy = async (req: Express.Request, res: Express.Response) => {
  try {
    const configurationError = getChatbotConfigurationError();
    if (configurationError) {
      res.status(503).json({ error: configurationError });
      return;
    }

    const context = await createAuthenticatedContext(req, res, 'chatbot');
    if (!context.user) {
      res.sendStatus(403);
      return;
    }

    if (!req.body?.question) {
      res.status(400).json({ error: 'Chatbot request body is missing or has no question' });
      return;
    }

    const { question, chatId: clientChatId } = req.body;
    const chatId = clientChatId || 'default';

    const history = getOrCreateHistory(chatId);
    history.push({ role: 'user', content: question });
    trimHistory(history);

    let selectedModel = await resolveChatbotModel();

    const openaiBody = {
      model: selectedModel,
      max_tokens: CHATBOT_MAX_TOKENS,
      stream: true,
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        ...history.map((m) => ({
          role: m.role,
          content: m.content,
        })),
      ],
    };

    let response = await executeChatbotRequest(openaiBody);

    if (!response.ok) {
      let errText = await response.text();
      const shouldRetryWithDiscoveredModel = response.status === 404 && errText.includes('does not exist');

      if (shouldRetryWithDiscoveredModel) {
        const fallbackModel = await resolveChatbotModel(true);
        if (fallbackModel !== selectedModel) {
          selectedModel = fallbackModel;
          response = await executeChatbotRequest({
            ...openaiBody,
            model: selectedModel,
          });
          if (!response.ok) {
            errText = await response.text();
          }
        }
      }

      if (!response.ok) {
      logApp.error('OpenAI-compatible chatbot API error', {
        status: response.status,
        body: errText,
        endpoint: OPENAI_CHAT_COMPLETIONS_URL,
        model: selectedModel,
      });
      res.status(502).json({
        error: `Chatbot API returned ${response.status}`,
      });
      return;
      }
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache, no-transform');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');

    writeSseEvent(res, 'start');

    const reader = response.body?.getReader();
    if (!reader) {
      writeSseEvent(res, 'error', 'No response stream');
      writeSseEvent(res, 'end');
      res.end();
      return;
    }

    const decoder = new TextDecoder();
    let fullResponse = '';
    let buffer = '';

    const processSseLine = (line: string) => {
      if (!line.startsWith('data:')) return;

      const data = line.slice(5).trim();
      if (!data || data === '[DONE]') return;

      try {
        const parsed = JSON.parse(data);

        const text =
          parsed?.choices?.[0]?.delta?.content
          ?? parsed?.choices?.[0]?.message?.content
          ?? '';

        if (typeof text === 'string' && text.length > 0) {
          fullResponse += text;
          writeSseEvent(res, 'token', text);
        }
      } catch {
        // ignore malformed chunk
      }
    };

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          processSseLine(line);
        }
      }

      if (buffer.trim()) {
        processSseLine(buffer.trim());
      }
    } catch (streamErr) {
      logApp.error('Stream read error from OpenAI-compatible chatbot API', { cause: streamErr });
    }

    if (fullResponse) {
      history.push({ role: 'assistant', content: fullResponse });
      trimHistory(history);
    }

    writeSseEvent(res, 'metadata', { chatId, model: selectedModel });
    writeSseEvent(res, 'end');
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
      try {
        writeSseEvent(res, 'error', message);
        writeSseEvent(res, 'end');
      } catch {
        // response may already be closed
      }
      res.end();
    }

    setCookieError(res, message);
  }
};