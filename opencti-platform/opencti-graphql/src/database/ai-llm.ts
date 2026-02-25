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

const AI_ENABLED = conf.get('ai:enabled');
const AI_TYPE = conf.get('ai:type');
const AI_ENDPOINT = conf.get('ai:endpoint');
const AI_TOKEN = conf.get('ai:token');
const AI_MODEL = conf.get('ai:model');
const AI_MAX_TOKENS = conf.get('ai:max_tokens');
const AI_VERSION = conf.get('ai:version');
const AI_AZURE_INSTANCE = conf.get('ai:ai_azure_instance');
const AI_AZURE_DEPLOYMENT = conf.get('ai:ai_azure_deployment');

// FORK: Anthropic API constants
const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_DEFAULT_MODEL = 'claude-sonnet-4-5-20250929';

let client: Mistral | OpenAI | AzureOpenAI | null = null;
let nlqChat: ChatOpenAI | ChatMistralAI | AzureChatOpenAI | ChatAnthropic | null = null;
// FORK: For anthropic streaming queries, we use raw fetch (no SDK client needed).
let anthropicEnabled = false;

if (AI_ENABLED && AI_TOKEN) {
  switch (AI_TYPE) {
    case 'anthropic': { // FORK: Anthropic/Claude support via @langchain/anthropic
      anthropicEnabled = true;
      const anthropicModel = AI_MODEL || 'claude-sonnet-4-5-20250929';
      nlqChat = new ChatAnthropic({
        model: anthropicModel,
        apiKey: AI_TOKEN,
        temperature: 0,
        maxTokens: 4096,
        ...(isEmptyField(AI_ENDPOINT) ? {} : { anthropicApiUrl: AI_ENDPOINT }),
      });
      break;
    }

    case 'mistralai':
      client = new Mistral({
        serverURL: isEmptyField(AI_ENDPOINT) ? undefined : AI_ENDPOINT,
        apiKey: AI_TOKEN,
        /* uncomment if you need low level debug on AI
        debugLogger: {
          log: (message, args) => logApp.info(`[AI] log ${message}`, { message }),
          group: (label) => logApp.info(`[AI] group ${label} start.`),
          groupEnd: () => logApp.info('[AI] group end.'),
        } */
      });

      if (AI_ENDPOINT.includes('https://api.mistral.ai')) {
        // Official MistralAI API
        nlqChat = new ChatMistralAI({
          model: AI_MODEL,
          apiKey: AI_TOKEN,
          temperature: 0,
        });
      } else {
        // Mistral model deployed via vLLM (OpenAI-compatible)
        nlqChat = new ChatOpenAI({
          model: AI_MODEL,
          apiKey: AI_TOKEN,
          temperature: 0,
          configuration: {
            baseURL: `${AI_ENDPOINT}/v1`,
          },
        });
      }

      break;

    case 'openai':
      client = new OpenAI({
        apiKey: AI_TOKEN,
        ...(isEmptyField(AI_ENDPOINT) ? {} : { baseURL: AI_ENDPOINT }),
      });

      nlqChat = new ChatOpenAI({
        model: AI_MODEL,
        apiKey: AI_TOKEN,
        temperature: 0,
        configuration: {
          baseURL: AI_ENDPOINT || undefined,
        },
      });

      break;

    case 'azureopenai':
      client = new AzureOpenAI({
        apiKey: AI_TOKEN,
        ...(isEmptyField(AI_ENDPOINT) ? {} : { baseURL: AI_ENDPOINT }),
        ...(isEmptyField(AI_VERSION) ? {} : { apiVersion: AI_VERSION }),
      });

      nlqChat = new AzureChatOpenAI({
        azureOpenAIApiKey: AI_TOKEN,
        azureOpenAIApiVersion: AI_VERSION,
        azureOpenAIApiInstanceName: AI_AZURE_INSTANCE,
        azureOpenAIApiDeploymentName: AI_AZURE_DEPLOYMENT,
        temperature: 0,
      });

      break;

    default:
      throw UnsupportedError('Not supported AI type (currently support: mistralai, openai, azureopenai, anthropic)', { type: AI_TYPE });
  }
}

// Query MistralAI (Streaming)
export const queryMistralAi = async (busId: string | null, systemMessage: string, userMessage: string, user: AuthUser) => {
  if (!client) {
    throw UnsupportedError('Incorrect AI configuration', { enabled: AI_ENABLED, type: AI_TYPE, endpoint: AI_ENDPOINT, model: AI_MODEL });
  }
  try {
    logApp.debug('[AI] Querying MistralAI with prompt', { questionStart: userMessage.substring(0, 100) });
    const request: ChatCompletionStreamRequest = {
      model: AI_MODEL,
      temperature: 0,
      messages: [
        { role: 'system', content: systemMessage },
        { role: 'user', content: truncate(userMessage, AI_MAX_TOKENS, false) },
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
export const queryChatGpt = async (busId: string | null, developerMessage: string, userMessage: string, user: AuthUser) => {
  if (!client) {
    throw UnsupportedError('Incorrect AI configuration', { enabled: AI_ENABLED, type: AI_TYPE, endpoint: AI_ENDPOINT, model: AI_MODEL });
  }
  try {
    logApp.info('[AI] Querying OpenAI with prompt', { type: AI_TYPE });
    const response = await (client as OpenAI)?.chat.completions.create({
      model: AI_MODEL,
      messages: [
        { role: (AI_TYPE === 'azureopenai') ? 'system' : 'developer', content: developerMessage },
        { role: 'user', content: truncate(userMessage, AI_MAX_TOKENS, false) },
      ],
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
      return content;
    }
    logApp.error('[AI] No response from OpenAI', { busId, developerMessage, userMessage });
    return 'No response from OpenAI';
  } catch (err) {
    logApp.error('[AI] Cannot query OpenAI', { cause: err });
    // eslint-disable-next-line @typescript-eslint/ban-ts-comment
    // @ts-expect-error
    return `An error occurred: ${err.toString()}`;
  }
};

// FORK: Query Anthropic/Claude (Streaming via raw fetch)
export const queryAnthropic = async (busId: string | null, systemMessage: string, userMessage: string, user: AuthUser) => {
  if (!anthropicEnabled || !AI_TOKEN) {
    throw UnsupportedError('Incorrect AI configuration for Anthropic', { enabled: AI_ENABLED, type: AI_TYPE, model: AI_MODEL });
  }
  try {
    const model = AI_MODEL || ANTHROPIC_DEFAULT_MODEL;
    const maxTokens = AI_MAX_TOKENS || 4096;
    logApp.debug('[AI] Querying Anthropic with prompt', { questionStart: userMessage.substring(0, 100), model });
    const response = await fetch(AI_ENDPOINT || ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': AI_TOKEN,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model,
        max_tokens: maxTokens,
        stream: true,
        system: systemMessage,
        messages: [
          { role: 'user', content: truncate(userMessage, AI_MAX_TOKENS, false) },
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

// Generic AI Query Handler
export const queryAi = async (busId: string | null, developerMessage: string | null, userMessage: string, user: AuthUser) => {
  const finalDeveloperMessage = developerMessage || 'You are an assistant helping a cyber threat intelligence analyst to better understand cyber threat intelligence data.';
  switch (AI_TYPE) {
    case 'anthropic': // FORK
      return queryAnthropic(busId, finalDeveloperMessage, userMessage, user);
    case 'mistralai':
      return queryMistralAi(busId, finalDeveloperMessage, userMessage, user);
    case 'azureopenai':
    case 'openai':
      return queryChatGpt(busId, finalDeveloperMessage, userMessage, user);
    default:
      throw UnsupportedError('Not supported AI type', { type: AI_TYPE });
  }
};

// NLQ AI Query with LangChain's Chat Models
export const queryNLQAi = async (promptValue: ChatPromptValueInterface) => {
  const badAiConfigError = UnsupportedError('Incorrect AI configuration for NLQ', {
    enabled: AI_ENABLED,
    type: AI_TYPE,
    endpoint: AI_ENDPOINT,
    model: AI_MODEL,
  });
  if (!nlqChat) {
    throw badAiConfigError;
  }

  await addNlqQueryCount();

  logApp.info('[NLQ] Querying AI model for structured output');
  try {
    // Cast to ChatOpenAI to resolve union type incompatibility with withStructuredOutput overloads
    const chat = nlqChat as ChatOpenAI;
    return await chat.withStructuredOutput<Output>(OutputSchema).invoke(promptValue);
  } catch (err) {
    if (err instanceof AuthenticationError) {
      throw badAiConfigError;
    }
    throw UnknownError('Error when calling the NLQ model', { cause: err, promptValue });
  }
};
