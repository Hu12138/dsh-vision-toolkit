/**
 * 核心转换逻辑：把消息里的图片块替换成 GLM-4V 的视觉分析文本。
 * 独立成模块以便单元测试；index.js 负责接入 llm/stream waterfall。
 */
import { readFileSync } from 'node:fs';

/** 默认描述提示词 */
export const DEFAULT_PROMPT =
  '请详细描述这张图片的内容：包括所有可见文字、界面元素、布局、颜色和整体状态。如果是截图，请描述页面结构和渲染是否正常。';

/**
 * 分析一张图片（通过智谱 GLM-4V），返回文字描述。
 * @param {object} opts - { apiKey, model, endpoint, prompt, timeoutMs }
 * @param {object} ref - 图片附件引用 { attachmentId, mediaType, name, width, height }
 * @param {(ref)=>string|undefined} imageHostPath - 由 ctx.attachments 提供
 */
export async function describeImage(opts, ref, imageHostPath) {
  if (!ref || !ref.attachmentId) throw new Error('image block 缺少 attachment ref');
  const hostPath = imageHostPath(ref);
  if (!hostPath) throw new Error('无法解析图片附件路径');
  const bytes = readFileSync(hostPath);
  const mime = ref.mediaType || 'image/png';
  const dataUrl = `data:${mime};base64,${bytes.toString('base64')}`;

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), opts.timeoutMs);
  try {
    const resp = await fetch(opts.endpoint, {
      method: 'POST',
      signal: ctl.signal,
      headers: {
        Authorization: `Bearer ${opts.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: opts.model,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'image_url', image_url: { url: dataUrl } },
              { type: 'text', text: opts.prompt },
            ],
          },
        ],
      }),
    });
    if (!resp.ok) {
      const body = await resp.text().catch(() => '');
      throw new Error(`vision api ${resp.status}: ${String(body).slice(0, 140)}`);
    }
    const json = await resp.json();
    const c = json?.choices?.[0]?.message?.content;
    const text = Array.isArray(c)
      ? c.map((x) => (x && typeof x.text === 'string' ? x.text : '')).join('')
      : typeof c === 'string'
        ? c
        : JSON.stringify(c ?? '');
    const name = ref.name ? `（${ref.name}）` : '';
    return `[图片分析${name}：${text}]`;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 遍历消息，把每个图片块替换为视觉分析文本。
 * @param {Array} messages - LLM 请求消息数组
 * @param {object} opts - 同上
 * @param {object} deps - { imageHostPath }
 * @param {object} [fallback] - { keepImage: true } 失败时保留原图（走模型默认处理）
 * @returns {Promise<Array>} 新消息数组
 */
export async function transformMessages(messages, opts, deps, fallback = { keepImage: true }) {
  const hasImage = messages.some(
    (m) => Array.isArray(m?.content) && m.content.some((b) => b?.type === 'image'),
  );
  if (!hasImage) return messages;

  const results = await Promise.all(
    messages.map(async (m) => {
      if (!Array.isArray(m?.content) || !m.content.some((b) => b?.type === 'image')) return m;
      const content = [];
      for (const block of m.content) {
        if (block?.type !== 'image') {
          content.push(block);
          continue;
        }
        try {
          content.push({ type: 'text', text: await describeImage(opts, block.attachment, deps.imageHostPath) });
        } catch (error) {
          if (fallback.keepImage) {
            content.push(block);
          } else {
            content.push({ type: 'text', text: `[图片分析失败：${String(error.message || error).slice(0, 160)}]` });
          }
        }
      }
      return { ...m, content };
    }),
  );
  return results;
}
