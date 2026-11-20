/**
 * dsh-vision-bridge：在 llm/stream waterfall 中把图片块替换为
 * GLM-4V 视觉分析文本，从而"图片不进上游模型、只发文本"。
 *
 * 上游模型仍需在 provider 配置里声明 input: [text, image]（准入需要），
 * 但真正的图片载荷在本插件处被拦截并替换。
 *
 * 零依赖：不 import 任何第三方包，安装到任意位置都能解析。
 */
import { transformMessages, DEFAULT_PROMPT } from './core.mjs';

export function apply(ctx, config = {}) {
  const opts = {
    apiKey: config.apiKey || '',
    model: config.model || 'glm-4v-flash',
    prompt: config.prompt || DEFAULT_PROMPT,
    endpoint: config.endpoint || 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    timeoutMs: config.timeoutMs || 30000,
  };

  const listener = (options, next) => {
    const messages = options?.messages;
    const hasImage =
      Array.isArray(messages) &&
      messages.some((m) => Array.isArray(m?.content) && m.content.some((b) => b?.type === 'image'));
    if (!hasImage) return next();

    // 异步工作必须在"开始消费流"时执行：返回异步生成器（本身是 async iterable），
    // 在第一个 chunk 之前完成图片→文本替换，再 yield 下游流。
    return (async function* () {
      try {
        const transformed = await transformMessages(
          messages,
          opts,
          { imageHostPath: (ref) => ctx.attachments?.imageHostPath?.(ref) },
          { keepImage: config.keepImageOnError !== false },
        );
        if (transformed !== messages) options.messages = transformed;
      } catch {
        // 任何异常都不破坏管线；图片保持原样走默认处理
      }
      yield* next();
    })();
  };

  ctx.on('llm/stream', listener);
  return () => ctx.off('llm/stream', listener);
}
