import { ChatAnthropic } from '@langchain/anthropic';
import type { ChatPromptValueInterface } from '@langchain/core/prompt_values';
import { ChatMistralAI } from '@langchain/mistralai';
import { AzureChatOpenAI, ChatOpenAI } from '@langchain/openai';
import { Mistral } from '@mistralai/mistralai';
import type { ChatCompletionStreamRequest } from '@mistralai/mistralai/models/components';
import { AuthenticationError, AzureOpenAI, OpenAI } from 'openai';
import conf, { BUS_TOPICS, logApp } from '../config/conf';
import { UnknownError, UnsupportedError } from '../config/errors';
import { OutputSchema } from '../modules/ai/ai-nlq-schema';
import type { Output } from '../modules/ai/ai-nlq-schema';
import { AI_BUS } from '../modules/ai/ai-types';
import type { AuthUser } from '../types/user';
import { truncate } from '../utils/format';
import { notify } from './redis';
import { isEmptyField } from './utils';
import { addNlqQueryCount } from '../manager/telemetryManager';

const AI_CONFIG = {
  enabled: conf.get('ai:enabled'),
  type: `${conf.get('ai:type') ?? ''}`.toLowerCase(),
  endpoint: conf.get('ai:endpoint'),
  token: conf.get('ai:token'),
  model: conf.get('ai:model'),
  maxTokens: conf.get('ai:max_tokens'),
  version: conf.get('ai:version'),
  azureInstance: conf.get('ai:ai_azure_instance'),
  azureDeployment: conf.get('ai:ai_azure_deployment'),
};

const OPENAI_COMPATIBLE_TYPES = new Set(['openai']);
const PROVIDER_LABELS: Record<string, string> = {
  azureopenai: 'Azure OpenAI',
  mistralai: 'MistralAI',
  anthropic: 'Anthropic',
  openai: 'OpenAI',
};
const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';

const normalizeOpenAiEndpoint = (endpoint: string) => {
  const normalizedEndpoint = endpoint.replace(/\/+$/, '');
  return normalizedEndpoint.endsWith('/v1') ? normalizedEndpoint : `${normalizedEndpoint}/v1`;
};

const resolveAiConfig = () => {
  const usesCustomOpenAiEndpoint = AI_CONFIG.type === 'openai' && !isEmptyField(AI_CONFIG.endpoint);
  const endpoint = usesCustomOpenAiEndpoint
    ? normalizeOpenAiEndpoint(AI_CONFIG.endpoint)
    : AI_CONFIG.endpoint;

  return {
    endpoint,
    token: AI_CONFIG.token,
    model: AI_CONFIG.model,
  };
};

const AI = {
  ...AI_CONFIG,
  ...resolveAiConfig(),
};

const hasAiConfig = () => {
  switch (AI.type) {
    case 'anthropic':
    case 'azureopenai':
    case 'mistralai':
    case 'openai':
      return !isEmptyField(AI.token);
    default:
      return false;
  }
};

const isOpenAiCompatibleType = () => OPENAI_COMPATIBLE_TYPES.has(AI.type);

const aiErrorContext = () => ({
  enabled: AI.enabled,
  type: AI.type,
  endpoint: AI.endpoint,
  model: AI.model,
});

const getProviderLabel = () => PROVIDER_LABELS[AI.type] ?? 'OpenAI';

const formatNlqResultForLog = (result: Output) => ({
  mode: result.mode,
  filtersCount: Array.isArray(result.filters) ? result.filters.length : 0,
  filters: result.filters,
});

let client: Mistral | OpenAI | AzureOpenAI | null = null;
let nlqChat: ChatOpenAI | ChatMistralAI | AzureChatOpenAI | ChatAnthropic | null = null;
// Anthropic streaming queries use raw fetch instead of the OpenAI SDK.
let anthropicEnabled = false;

if (AI.enabled && hasAiConfig()) {
  switch (AI.type) {
    case 'anthropic': {
      anthropicEnabled = true;
      const anthropicChat = new ChatAnthropic({
        model: AI.model,
        apiKey: AI.token,
        temperature: 0,
        maxTokens: 4096,
        ...(isEmptyField(AI.endpoint) ? {} : { anthropicApiUrl: AI.endpoint }),
      });
      // Anthropic rejects the default top_p sent by LangChain.
      const originalInvocationParams = anthropicChat.invocationParams.bind(anthropicChat);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      anthropicChat.invocationParams = function (options: any) {
        const params = originalInvocationParams(options);
        delete params.top_p;
        return params;
      };
      nlqChat = anthropicChat;
      break;
    }

    case 'mistralai':
      client = new Mistral({
        serverURL: isEmptyField(AI.endpoint) ? undefined : AI.endpoint,
        apiKey: AI.token,
        /* uncomment if you need low level debug on AI
        debugLogger: {
          log: (message, args) => logApp.info(`[AI] log ${message}`, { message }),
          group: (label) => logApp.info(`[AI] group ${label} start.`),
          groupEnd: () => logApp.info('[AI] group end.'),
        } */
      });

      if (AI.endpoint.includes('https://api.mistral.ai')) {
        // Official MistralAI API
        nlqChat = new ChatMistralAI({
          model: AI.model,
          apiKey: AI.token,
          temperature: 0,
        });
      } else {
        // Mistral model exposed through an OpenAI-compatible endpoint.
        nlqChat = new ChatOpenAI({
          model: AI.model,
          apiKey: AI.token,
          temperature: 0,
          configuration: {
            baseURL: `${AI.endpoint}/v1`,
          },
        });
      }

      break;

    case 'openai':
      if (!isOpenAiCompatibleType()) {
        throw UnsupportedError('Incorrect AI configuration', { type: AI.type });
      }
      client = new OpenAI({
        apiKey: AI.token,
        ...(isEmptyField(AI.endpoint) ? {} : { baseURL: AI.endpoint }),
      });

      nlqChat = new ChatOpenAI({
        model: AI.model,
        apiKey: AI.token,
        temperature: 0,
        configuration: {
          baseURL: AI.endpoint || undefined,
        },
      });

      break;

    case 'azureopenai':
      client = new AzureOpenAI({
        apiKey: AI.token,
        ...(isEmptyField(AI.endpoint) ? {} : { baseURL: AI.endpoint }),
        ...(isEmptyField(AI.version) ? {} : { apiVersion: AI.version }),
      });

      nlqChat = new AzureChatOpenAI({
        azureOpenAIApiKey: AI.token,
        azureOpenAIApiVersion: AI.version,
        azureOpenAIApiInstanceName: AI.azureInstance,
        azureOpenAIApiDeploymentName: AI.azureDeployment,
        temperature: 0,
      });

      break;

    default:
      throw UnsupportedError('Not supported AI type (currently support: mistralai, openai, azureopenai, anthropic)', { type: AI.type });
  }
}

// Query MistralAI (Streaming)
export const queryMistralAi = async (busId: string | null, systemMessage: string, userMessage: string, user: AuthUser) => {
  if (!client) {
    throw UnsupportedError('Incorrect AI configuration', aiErrorContext());
  }
  try {
    logApp.debug('[AI] Querying MistralAI with prompt', { questionStart: userMessage.substring(0, 100) });
    const request: ChatCompletionStreamRequest = {
      model: AI.model,
      temperature: 0,
      messages: [
        { role: 'system', content: systemMessage },
        { role: 'user', content: truncate(userMessage, AI.maxTokens, false) },
      ],
    };
    const response = await (client as Mistral)?.chat.stream(request);
    let content = '';
    if (response) {
      // eslint-disable-next-line no-restricted-syntax
      for await (const chunk of response) {
        if (chunk.data.choices[0].delta.content !== undefined) {
          const streamText = chunk.data.choices[0].delta.content;
          content += streamText;
          if (busId !== null) {
            await notify(BUS_TOPICS[AI_BUS].EDIT_TOPIC, { bus_id: busId, content }, user);
          }
        }
      }
      return content;
    }
    logApp.error('[AI] No response from MistralAI', { busId, systemMessage, userMessage });
    return 'No response from MistralAI';
  } catch (err) {
    logApp.error('[AI] Cannot query MistralAI', { cause: err });
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-expect-error
    return `An error occurred: ${err.toString()}`;
  }
};

// Query OpenAI (Streaming)
export const queryChatGpt = async (busId: string | null, systemMessage: string, userMessage: string, user: AuthUser) => {
  if (!client) {
    throw UnsupportedError('Incorrect AI configuration', aiErrorContext());
  }
  try {
    const messages: Array<{ role: 'system' | 'user'; content: string }> = [
      { role: 'system', content: systemMessage },
      { role: 'user', content: truncate(userMessage, AI.maxTokens, false) },
    ];
    logApp.info(`[AI] Querying ${getProviderLabel()}`, { type: AI.type, model: AI.model, endpoint: AI.endpoint, messageCount: messages.length, userMsgStart: userMessage.substring(0, 150) });
    const response = await (client as OpenAI)?.chat.completions.create({
      model: AI.model,
      messages,
      stream: true,
    });
    let content = '';
    if (response) {
      // eslint-disable-next-line no-restricted-syntax
      for await (const chunk of response) {
        if (chunk.choices[0]?.delta.content !== undefined) {
          const streamText = chunk.choices[0].delta.content;
          content += streamText;
          if (busId !== null) {
            await notify(BUS_TOPICS[AI_BUS].EDIT_TOPIC, { bus_id: busId, content }, user);
          }
        }
      }
      logApp.info(`[AI] ${getProviderLabel()} response received`, { type: AI.type, model: AI.model, responseLength: content.length });
      return content;
    }
    logApp.error('[AI] No response from OpenAI', { busId, model: AI.model, endpoint: AI.endpoint });
    return 'No response from OpenAI';
  } catch (err) {
    logApp.error('[AI] Cannot query OpenAI', { cause: err, model: AI.model, endpoint: AI.endpoint });
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-expect-error
    return `An error occurred: ${err.toString()}`;
  }
};

export const queryAnthropic = async (busId: string | null, systemMessage: string, userMessage: string, user: AuthUser) => {
  if (!anthropicEnabled || isEmptyField(AI.token)) {
    throw UnsupportedError('Incorrect AI configuration for Anthropic', { enabled: AI.enabled, type: AI.type, model: AI.model });
  }
  try {
    const model = AI.model;
    const maxTokens = AI.maxTokens || 4096;
    logApp.debug('[AI] Querying Anthropic with prompt', { questionStart: userMessage.substring(0, 100), model });
    const response = await fetch(AI.endpoint || ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': AI.token,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model,
        max_tokens: maxTokens,
        stream: true,
        system: systemMessage,
        messages: [
          { role: 'user', content: truncate(userMessage, AI.maxTokens, false) },
        ],
      }),
    });
    if (!response.ok) {
      const errorText = await response.text();
      logApp.error('[AI] Anthropic API error', { status: response.status, error: errorText });
      return `An error occurred: Anthropic API returned ${response.status}: ${errorText}`;
    }
    if (!response.body) {
      logApp.error('[AI] No response body from Anthropic', { busId });
      return 'No response from Anthropic';
    }
    let content = '';
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    // eslint-disable-next-line no-constant-condition
    while (true) {
      // eslint-disable-next-line no-await-in-loop
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';
      // eslint-disable-next-line no-restricted-syntax
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const jsonStr = line.slice(6).trim();
          if (jsonStr === '[DONE]') break;
          try {
            const event = JSON.parse(jsonStr);
            if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') {
              const streamText = event.delta.text;
              content += streamText;
              if (busId !== null) {
                // eslint-disable-next-line no-await-in-loop
                await notify(BUS_TOPICS[AI_BUS].EDIT_TOPIC, { bus_id: busId, content }, user);
              }
            }
          } catch (_parseErr) {
            // Ignore non-JSON lines (event: lines, empty lines, etc.)
          }
        }
      }
    }
    return content || 'No response from Anthropic';
  } catch (err) {
    logApp.error('[AI] Cannot query Anthropic', { cause: err });
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-expect-error
    return `An error occurred: ${err.toString()}`;
  }
};

export const queryAi = async (busId: string | null, systemMessage: string | null, userMessage: string, user: AuthUser) => {
  const finalSystemMessage = systemMessage || 'You are an assistant helping a cyber threat intelligence analyst to better understand cyber threat intelligence data.';
  switch (AI.type) {
    case 'anthropic':
      return queryAnthropic(busId, finalSystemMessage, userMessage, user);
    case 'mistralai':
      return queryMistralAi(busId, finalSystemMessage, userMessage, user);
    case 'azureopenai':
    case 'openai':
      return queryChatGpt(busId, finalSystemMessage, userMessage, user);
    default:
      throw UnsupportedError('Not supported AI type', { type: AI.type });
  }
};

export const queryNLQAi = async (promptValue: ChatPromptValueInterface) => {
  const badAiConfigError = UnsupportedError('Incorrect AI configuration for NLQ', {
    enabled: AI.enabled,
    type: AI.type,
    endpoint: AI.endpoint,
    model: AI.model,
  });
  if (!nlqChat) {
    throw badAiConfigError;
  }

  await addNlqQueryCount();

  logApp.info('[AI-NLQ] Querying AI model for structured output', { type: AI.type, model: AI.model, endpoint: AI.endpoint });
  try {
    // Anthropic is more reliable here with bindTools than with strict structured output parsing.
    if (AI.type === 'anthropic') {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const chat = nlqChat as any;
      const bound = chat.bindTools(
        [{ name: 'nlq_output', schema: OutputSchema, description: 'Build a structured OpenCTI query' }],
        { tool_choice: { type: 'tool', name: 'nlq_output' } }
      );
      const msg = await bound.invoke(promptValue);
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const args = msg.tool_calls?.[0]?.args ?? {} as any;
      if (args.filters && !Array.isArray(args.filters)) {
        const nested = typeof args.filters === 'string' ? JSON.parse(args.filters) : args.filters;
        if (nested.filters && Array.isArray(nested.filters)) {
          args.mode = nested.mode || args.mode;
          args.filters = nested.filters;
        }
      }
      delete args.filterGroups; // Remove extra fields not in OutputSchema
      logApp.info('[AI-NLQ] AI response received (anthropic)', formatNlqResultForLog(args as Output));
      return args as Output;
    }
    // Cast to any to bypass LangChain union overload incompatibilities here.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const chat = nlqChat as any;
    const result = await chat.withStructuredOutput(OutputSchema).invoke(promptValue) as Output;
    logApp.info('[AI-NLQ] AI response received', { type: AI.type, ...formatNlqResultForLog(result) });
    return result;
  } catch (err) {
    logApp.error('[AI-NLQ] Error in queryNLQAi', { cause: err, aiType: AI.type, model: AI.model, endpoint: AI.endpoint });
    if (err instanceof AuthenticationError) {
      throw badAiConfigError;
    }
    throw UnknownError('Error when calling the NLQ model', { cause: err, promptValue });
  }
};
