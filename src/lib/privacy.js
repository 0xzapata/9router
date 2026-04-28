import { getPrivacySettings } from "@/lib/privacyDb";

const PATTERNS = {
  ipv4: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/g,
  ipv6: /\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,7}:|\b(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}\b|\b(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}\b|\b(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}\b|\b(?:[0-9a-fA-F]{1,4}:)(?::[0-9a-fA-F]{1,4}){1,6}\b|\b:(?::[0-9a-fA-F]{1,4}){1,7}\b|\b::(?:[fF]{4}:)?(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/g,
  email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/g,
  md5: /\b[a-fA-F0-9]{32}\b/g,
  sha1: /\b[a-fA-F0-9]{40}\b/g,
  sha256: /\b[a-fA-F0-9]{64}\b/g,
  awsKey: /\b(AKIA|ABIA|ACCA|ASIA)[0-9A-Z]{16}\b/g,
  genericApiKey: /\b(?:api[_-]?key|secret[_-]?key|token|auth[_-]?token)\s*[:=]\s*['"]?([a-zA-Z0-9_\-]{20,})['"]?/gi,
  hostname: /\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b/g
};

function generatePlaceholder(type, index) {
  return `[${type.toUpperCase()}_${index.toString().padStart(4, '0')}]`;
}

export async function anonymizeText(text, customPatterns = []) {
  if (typeof text !== 'string') return text;

  const settings = await getPrivacySettings();
  if (!settings.privacyEnabled) return text;

  let result = text;
  const replacements = [];

  const patternsToApply = [];

  if (settings.anonymizeIps) {
    patternsToApply.push({ type: 'IP', regex: PATTERNS.ipv4 });
    patternsToApply.push({ type: 'IPV6', regex: PATTERNS.ipv6 });
  }

  if (settings.anonymizeEmails) {
    patternsToApply.push({ type: 'EMAIL', regex: PATTERNS.email });
  }

  if (settings.anonymizeHashes) {
    patternsToApply.push({ type: 'HASH_MD5', regex: PATTERNS.md5 });
    patternsToApply.push({ type: 'HASH_SHA1', regex: PATTERNS.sha1 });
    patternsToApply.push({ type: 'HASH_SHA256', regex: PATTERNS.sha256 });
  }

  if (settings.anonymizeApiKeys) {
    patternsToApply.push({ type: 'AWS_KEY', regex: PATTERNS.awsKey });
    patternsToApply.push({ type: 'API_KEY', regex: PATTERNS.genericApiKey });
  }

  if (settings.anonymizeHostnames) {
    patternsToApply.push({ type: 'HOST', regex: PATTERNS.hostname });
  }

  if (settings.anonymizeCustom && settings.anonymizeCustom.length > 0) {
    for (const pattern of settings.anonymizeCustom) {
      try {
        const regex = new RegExp(pattern, 'gi');
        patternsToApply.push({ type: 'CUSTOM', regex });
      } catch (e) {
        console.warn(`[Privacy] Invalid custom pattern: ${pattern}`);
      }
    }
  }

  const allReplacements = {};

  for (const { type, regex } of patternsToApply) {
    result = result.replace(regex, (match) => {
      if (!allReplacements[match]) {
        const placeholder = generatePlaceholder(type, Object.keys(allReplacements).length + 1);
        allReplacements[match] = placeholder;
        replacements.push({ original: match, anonymized: placeholder, type });
      }
      return allReplacements[match];
    });
  }

  if (replacements.length > 0) {
    const totalRedactions = replacements.length;
    const types = replacements.map(r => r.type).join(', ');
    console.log(`[Privacy] Redacted ${totalRedactions} item(s) [${types}] in request`);
    for (const { original, anonymized, type } of replacements) {
      console.log(`[Privacy]   [${type}] ${original} -> ${anonymized}`);
    }
  }

  return result;
}

export async function anonymizeMessages(messages) {
  if (!Array.isArray(messages)) return messages;

  const anonymizedMessages = [];
  for (const message of messages) {
    const anonymizedMessage = { ...message };
    if (anonymizedMessage.content) {
      if (typeof anonymizedMessage.content === 'string') {
        anonymizedMessage.content = await anonymizeText(anonymizedMessage.content);
      } else if (Array.isArray(anonymizedMessage.content)) {
        anonymizedMessage.content = await Promise.all(
          anonymizedMessage.content.map(async (part) => {
            if (part.type === 'text') {
              return {
                ...part,
                text: await anonymizeText(part.text)
              };
            }
            return part;
          })
        );
      }
    }
    anonymizedMessages.push(anonymizedMessage);
  }

  return anonymizedMessages;
}

export async function anonymizeRequestBody(body) {
  if (!body || typeof body !== 'object') return body;

  const anonymizedBody = { ...body };

  if (anonymizedBody.messages) {
    anonymizedBody.messages = await anonymizeMessages(anonymizedBody.messages);
  }

  if (anonymizedBody.input) {
    anonymizedBody.input = await anonymizeMessages(anonymizedBody.input);
  }

  return anonymizedBody;
}
