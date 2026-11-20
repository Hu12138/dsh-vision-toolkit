# dsh-vision-bridge

DSH 插件：在上游模型调用前，把消息里的**图片块替换为 GLM-4V 的视觉分析文本**。

- 图片**不会**发送给上游模型——只在请求管线（`llm/stream` waterfall）中被拦截、分析、转文本。
- 零依赖（无第三方 npm 依赖），安装到任意位置即可解析。
- 失败兜底：视觉 API 出错时默认保留原图，走上游模型默认处理。

## 配置项

| 字段 | 默认 | 说明 |
|---|---|---|
| `apiKey` | 必填 | 智谱开放平台 API Key |
| `model` | `glm-4v-flash` | 视觉模型（免费；可换 `glm-4.6v-flash` 等） |
| `prompt` | 内置描述提示词 | 视觉分析的提问文本 |
| `endpoint` | `https://open.bigmodel.cn/api/paas/v4/chat/completions` | 智谱对话补全接口 |
| `timeoutMs` | `30000` | 单次视觉请求超时 |
| `keepImageOnError` | `true` | 视觉失败时保留原图（`false` 则替换为失败说明） |

## 工作原理

```
粘贴图片 → 准入通过（模型声明 input:[text,image]）
  → llm/stream waterfall（本插件）
    → 读存档图片 → 调 GLM-4V → 替换成 [图片分析：...] 文本
  → 下游模型只收到文本
```

- 异步处理采用 DSH 官方模式（异步生成器 + `yield* next()`），不破坏 stream 协议。
- 无图片的消息走快速路径，零开销。

## 安装

```bash
dsh plugin --profile web add /path/to/vision-bridge
```

然后在 `cordis.patch.yml`：

```yaml
- insert:
    - id: vision-bridge
      name: "dsh-vision-bridge"
      config:
        apiKey: "你的智谱Key"
        model: glm-4v-flash
```

上游模型需声明 `input: [text, image]`（准入需要；图片实际会被本插件替换，不会上行的模型）。

## 测试

```bash
node --check index.js && node --check core.mjs
```

核心转换逻辑在 `core.mjs`（`transformMessages` / `describeImage`），可直接单元测试。

## License

MIT
