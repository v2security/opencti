import type Express from 'express';
import nconf from 'nconf';
import { createAuthenticatedContext } from './httpAuthenticatedContext';
import { logApp } from '../config/conf';
import { setCookieError } from './httpUtils';
import { isEmptyField } from '../database/utils';

type ChatHistoryMessage = {
  role: 'user' | 'assistant';
  content: string;
};

const CHATBOT_CONFIG = {
  enabled: nconf.get('chatbot:enabled') ?? true,
  type: `${nconf.get('chatbot:type') ?? ''}`.toLowerCase(),
  endpoint: nconf.get('chatbot:endpoint') ?? '',
  token: nconf.get('chatbot:token') ?? '',
  model: nconf.get('chatbot:model') ?? '',
  aiModel: nconf.get('ai:model') ?? '',
  maxTokens: Number(nconf.get('chatbot:max_tokens') ?? 4096),
};
const SUPPORTED_CHATBOT_TYPES = new Set(['openai']);

const toOpenAiBaseUrl = (endpoint: string) => {
  const normalizedEndpoint = endpoint.replace(/\/+$/, '');
  return normalizedEndpoint.endsWith('/v1')
    ? normalizedEndpoint
    : `${normalizedEndpoint}/v1`;
};

const OPENAI_BASE_URL = isEmptyField(CHATBOT_CONFIG.endpoint)
  ? ''
  : toOpenAiBaseUrl(CHATBOT_CONFIG.endpoint);

const OPENAI_CHAT_COMPLETIONS_URL = `${OPENAI_BASE_URL}/chat/completions`;
const OPENAI_MODELS_URL = `${OPENAI_BASE_URL}/models`;

let resolvedChatbotModel: string | null = null;
let resolvingChatbotModelPromise: Promise<string> | null = null;

const getChatbotConfigError = () => {
  if (!CHATBOT_CONFIG.enabled) {
    return 'Chatbot is disabled by configuration.';
  }
  if (!SUPPORTED_CHATBOT_TYPES.has(CHATBOT_CONFIG.type)) {
    return `Unsupported chatbot type "${CHATBOT_CONFIG.type}". Supported types: openai.`;
  }
  if (isEmptyField(CHATBOT_CONFIG.endpoint)) {
    return 'Chatbot endpoint is not configured.';
  }
  if (isEmptyField(CHATBOT_CONFIG.token)) {
    return 'Chatbot token is not configured.';
  }
  return null;
};

export const XTM_ONE_CHATBOT_URL = OPENAI_BASE_URL;

const SYSTEM_PROMPT = `
You are V2-AI, an expert AI assistant specialized in Cyber Threat Intelligence (CTI).

You operate inside V2TIP, a Threat Intelligence platform. Your role is to help analysts with:

- Understanding threat actors, malware, campaigns, vulnerabilities, and attack patterns
- Interpreting STIX objects, entities, and relationships
- Writing, reviewing, and summarizing CTI reports
- Querying the platform and explaining results
- IOC, TTP, CVE, MITRE ATT&CK, and detection-related questions
- General cybersecurity analysis

Guidelines:
- Be concise, precise, and professional
- Prefer facts over speculation
- If information is uncertain or incomplete, state that clearly
- Ask clarifying questions when needed
- Use Markdown when helpful
- Do not invent data or unsupported conclusions
`;

// Conversation state stays in memory only and is reset when the process restarts.
const conversationHistory = new Map<string, ChatHistoryMessage[]>();
const MAX_HISTORY_PER_CHAT = 40;
const MAX_CHATS = 500;

const getPreferredModels = () => [CHATBOT_CONFIG.model, CHATBOT_CONFIG.aiModel]
  .filter((model): model is string => typeof model === 'string' && model.trim().length > 0);

const getAuthHeaders = () => ({
  'Content-Type': 'application/json',
  Authorization: `Bearer ${CHATBOT_CONFIG.token}`,
});

const fetchModels = async () => {
  const response = await fetch(OPENAI_MODELS_URL, {
    method: 'GET',
    headers: getAuthHeaders(),
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

const resolveModel = async (forceRefresh = false) => {
  const preferredModels = getPreferredModels();
  const fallbackModel = preferredModels[0] ?? CHATBOT_CONFIG.model;

  if (!forceRefresh && resolvedChatbotModel) {
    return resolvedChatbotModel;
  }

  if (!forceRefresh && resolvingChatbotModelPromise) {
    return resolvingChatbotModelPromise;
  }

  const resolvePromise = (async () => {
    try {
      const availableModels = await fetchModels();
      if (availableModels.length === 0) {
        return fallbackModel;
      }

      const matchedModel = preferredModels.find((model) => availableModels.includes(model));
      if (matchedModel) {
        return matchedModel;
      }

      const selectedModel = availableModels[0];
      logApp.warn('Configured chatbot model is not served by the OpenAI-compatible endpoint, falling back to an available model', {
        configuredModel: CHATBOT_CONFIG.model,
        aiModel: CHATBOT_CONFIG.aiModel,
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

const requestChatCompletion = async (body: Record<string, unknown>) => {
  return fetch(OPENAI_CHAT_COMPLETIONS_URL, {
    method: 'POST',
    headers: getAuthHeaders(),
    body: JSON.stringify(body),
  });
};

const buildChatBody = (model: string, history: ChatHistoryMessage[]) => ({
  model,
  max_tokens: CHATBOT_CONFIG.maxTokens,
  stream: true,
  messages: [
    { role: 'system', content: SYSTEM_PROMPT },
    ...history.map((message) => ({
      role: message.role,
      content: message.content,
    })),
  ],
});

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
  const configurationError = getChatbotConfigError();
  if (configurationError) {
    res.status(503).json({ isStreaming: false, error: configurationError });
    return;
  }

  const model = await resolveModel();

  res.json({
    isStreaming: true,
    endpoint: OPENAI_BASE_URL,
    model,
  });
};

export const getChatbotProxy = async (req: Express.Request, res: Express.Response) => {
  try {
    const configurationError = getChatbotConfigError();
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

    let selectedModel = await resolveModel();
    const requestBody = buildChatBody(selectedModel, history);
    logApp.info('[AI-ChatBOT] Sending request to AI', { model: selectedModel, endpoint: OPENAI_BASE_URL, historySize: history.length });
    let response = await requestChatCompletion(requestBody);

    if (!response.ok) {
      let errText = await response.text();
      const shouldRetryWithDiscoveredModel = response.status === 404 && errText.includes('does not exist');

      if (shouldRetryWithDiscoveredModel) {
        const fallbackModel = await resolveModel(true);
        if (fallbackModel !== selectedModel) {
          selectedModel = fallbackModel;
          response = await requestChatCompletion(buildChatBody(selectedModel, history));
          if (!response.ok) {
            errText = await response.text();
          }
        }
      }

      if (!response.ok) {
        logApp.error('[AI-ChatBOT] OpenAI-compatible API error', {
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

    const readChunkText = (payload: unknown) => {
      if (typeof payload !== 'object' || payload === null) {
        return '';
      }
      const parsed = payload as {
        choices?: Array<{
          delta?: { content?: string };
          message?: { content?: string };
        }>;
      };

      return parsed.choices?.[0]?.delta?.content
        ?? parsed.choices?.[0]?.message?.content
        ?? '';
    };

    const pushSseLine = (line: string, fullText: { value: string }) => {
      if (!line.startsWith('data:')) return;

      const data = line.slice(5).trim();
      if (!data || data === '[DONE]') return;

      try {
        const text = readChunkText(JSON.parse(data));
        if (typeof text !== 'string' || text.length === 0) return;

        fullText.value += text;
        writeSseEvent(res, 'token', text);
      } catch {
        // ignore malformed chunk
      }
    };

    const decoder = new TextDecoder();
    const fullResponse = { value: '' };
    let buffer = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          pushSseLine(line, fullResponse);
        }
      }

      if (buffer.trim()) {
        pushSseLine(buffer.trim(), fullResponse);
      }
    } catch (streamErr) {
      logApp.error('[AI-ChatBOT] Stream read error from OpenAI-compatible API', { cause: streamErr });
    }

    if (fullResponse.value) {
      logApp.info('[AI-ChatBOT] AI response received', { model: selectedModel, responseLength: fullResponse.value.length });
      history.push({ role: 'assistant', content: fullResponse.value });
      trimHistory(history);
    } else {
      logApp.warn('[AI-ChatBOT] AI returned empty response', { model: selectedModel, endpoint: OPENAI_BASE_URL });
    }

    writeSseEvent(res, 'metadata', { chatId, model: selectedModel });
    writeSseEvent(res, 'end');
    res.end();

    req.on('close', () => {
      reader.cancel().catch(() => {});
    });
  } catch (e: unknown) {
    logApp.error('[AI-ChatBOT] Error in chatbot proxy', { cause: e });
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