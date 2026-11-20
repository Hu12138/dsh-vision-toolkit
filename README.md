# dsh-vision-toolkit

给 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）补上"**浏览器 + 看图**"能力的免费方案集合。

> English abstract: A free toolkit that adds browser automation and image understanding to DeepSeek Harness — including the `vision-bridge` plugin that replaces image blocks with GLM-4V analysis text before they reach an upstream text-only model.

## 解决了什么

- **浏览器能力**：DSH 官方实验插件的安装与配置（Playwright MCP / Chrome DevTools MCP），每个会话独立的 Chromium。
- **看图能力（免费）**：通过智谱免费模型 GLM-4V-Flash 实现语义级图像理解（识别、问答、图表分析），不是单纯 OCR。
- **核心插件 `vision-bridge`**（本仓库开发）：当你粘贴图片时，图片**不会发给上游模型**——插件在请求管线中拦截，先调用 GLM-4V 分析，再把分析文本发给上游模型。节省载荷、避免文本模型处理图片的延迟。

## 组件

| 组件 | 类型 | 说明 |
|---|---|---|
| [`vision-bridge/`](./vision-bridge/) | DSH 插件（本仓库开发，零依赖） | 图片 → GLM-4V 分析文本 → 只发文本给上游模型 |
| `glm4v-mcp` | 第三方 npm 包（MIT） | 把 GLM-4V 封装成 MCP 工具 `analyze_image`，供模型按需看图 |
| DSH 官方浏览器插件 | npm 包（实验性） | `@deepseek-ai/dsh-browser-use` + `@deepseek-ai/dsh-experimental-browser-use-playwright-mcp` |

## 安装

前置：Node.js ≥ 20、一个可用的 DSH profile、[智谱开放平台免费 API Key](https://open.bigmodel.cn/usercenter/apikeys)（GLM-4V-Flash 免费，有速率限制）。

### 1. 浏览器插件

```bash
dsh plugin --profile web add "@deepseek-ai/dsh-browser-use@0.2.1-rc.2" \
  "@deepseek-ai/dsh-experimental-browser-use-playwright-mcp@0.2.1-rc.2"
```

### 2. 视觉 MCP 工具

```bash
npm i glm4v-mcp          # 建议装在工作区，避免每次 npx 下载
```

### 3. vision-bridge 插件

```bash
dsh plugin --profile web add /path/to/dsh-vision-toolkit/vision-bridge
```

### 4. 配置（编辑 `~/.dsh/profiles/web/cordis.patch.yml`）

```yaml
- insert:
    - id: browser-use
      name: "@deepseek-ai/dsh-browser-use"
    - id: browser-use-playwright
      name: "@deepseek-ai/dsh-experimental-browser-use-playwright-mcp"
      config:
        mode: launch
        headless: true
        executablePath: /usr/bin/google-chrome-stable   # 你的 Chrome 路径

- insert:
    - id: mcp-vision
      name: "@deepseek-ai/dsh-mcp-client"
      config:
        serverName: vision
        transport: stdio
        command: /path/to/node_modules/.bin/glm4v-mcp
        args: [--stdio]
        env:
          ZHIPU_API_KEY: "你的智谱Key"

- insert:
    - id: vision-bridge
      name: "dsh-vision-bridge"
      config:
        apiKey: "你的智谱Key"
        model: glm-4v-flash
```

同时给上游模型声明图片输入（准入需要，实际图片会被 vision-bridge 替换掉）：

```yaml
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      your-provider:
        apiKeyEnv: YOUR_API_KEY
        api: openai-completions
        baseURL: http://127.0.0.1:8001/v1
        models:
          - id: your-model
            name: your-model
            input: [text, image]     # 声明图片输入，让粘贴图片通过准入
```

> 注意：一次只挂载一个浏览器 provider（playwright / chrome-devtools 二选一）。

### 5. 生效

**重启 DSH GUI 或新建会话**——插件在会话创建/恢复时装载。

## 使用效果

- 聊天框**直接粘贴图片** → vision-bridge 自动分析 → 上游模型基于分析文本回答（图片载荷不上行）
- 浏览器截图 → 用 `analyze_image` 工具分析页面渲染、图表、报错弹窗
- 上传的普通文件 → 以只读路径存档，模型按需读取

## 注意事项

- **免费但有速率限制**：GLM-4V-Flash 高峰可能 429（限流），vision-bridge 失败时默认保留原图走上游默认处理，不会让消息发不出去。
- **隐私**：图片会发送到智谱云端处理；敏感页面慎用。替代方案是本机本地模型（无此隐私顾虑，但需要硬件）。
- **实验性**：vision-bridge 基于 `llm/stream` waterfall（与 DSH 内置插件同机制），但属于自定义开发，升级 DSH 时注意兼容性。

## 回滚

- vision-bridge：从 `cordis.patch.yml` 删除对应 insert 段即可。
- 浏览器/视觉 MCP：删除对应 insert 段 + `dsh plugin --profile web remove <包名>`。

## License

MIT（vision-bridge 插件部分）。

相关项目：[glm4v-mcp](https://www.npmjs.com/package/glm4v-mcp)（MIT）、[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)、[Playwright MCP](https://github.com/microsoft/playwright-mcp)。
