#!/usr/bin/env bash
# =====================================================================
# dsh-vision-toolkit 安装脚本（新机器 / 新用户部署用）
#
# 只安装本仓库的增量（视觉能力），不涉及上游模型配置——
# 模型在 DSH GUI 的设置里自己配即可。
#
# 用法:
#   bash setup.sh                 # 完整安装（浏览器 + 视觉 + vision-bridge）
#   bash setup.sh --no-browser    # 只要视觉能力，跳过浏览器插件
#   PROFILE=myprofile bash setup.sh   # 装到指定 profile（默认 web）
#
# 需要:
#   - 已安装 dsh CLI（npm i -g @deepseek-ai/dsh）
#   - 智谱开放平台免费 API Key（GLM-4V-Flash 免费）
# =====================================================================
set -euo pipefail

# ---------- 参数 ----------
PROFILE="${PROFILE:-web}"
INSTALL_BROWSER=1
for arg in "$@"; do
  case "$arg" in
    --no-browser) INSTALL_BROWSER=0 ;;
    --profile=*) PROFILE="${arg#*=}" ;;
    --help|-h) sed -n '2,12p' "$0"; exit 0 ;;
  esac
done

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
PROFILE_DIR="$DSH_HOME/profiles/$PROFILE"
PATCH="$PROFILE_DIR/cordis.patch.yml"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 默认 Chrome 路径（可被环境变量覆盖）
CHROME_BIN="${CHROME_BIN:-/usr/bin/google-chrome-stable}"

log()  { printf '\033[1;32m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[注意]\033[0m %s\n' "$*"; }

# ---------- 前置检查 ----------
command -v dsh >/dev/null || { echo "未找到 dsh CLI，请先安装: npm i -g @deepseek-ai/dsh"; exit 1; }
[ -d "$SCRIPT_DIR/vision-bridge" ] || { echo "请从 dsh-vision-toolkit 仓库目录运行本脚本"; exit 1; }
node -e "if(Number(process.versions.node.split('.')[0])<20){process.exit(1)}" || { echo "Node.js ≥ 20 是必需的"; exit 1; }

# ---------- 1) 创建 profile（不存在时自动创建） ----------
if [ ! -d "$PROFILE_DIR" ]; then
  log "profile '$PROFILE' 不存在，用内置模板自动创建…"
  DSH_HOME="$DSH_HOME" dsh --profile "$PROFILE" --dump-config >/dev/null
fi
log "profile 目录: $PROFILE_DIR"

# ---------- 2) 收集必要配置（只有视觉相关） ----------
read -rp "智谱 API Key（GLM-4V-Flash 免费，https://open.bigmodel.cn 获取）: " ZHIPU_KEY
[ -n "$ZHIPU_KEY" ] || { echo "智谱 API Key 必填"; exit 1; }
read -rp "视觉模型（默认 glm-4v-flash）: " VISION_MODEL
VISION_MODEL="${VISION_MODEL:-glm-4v-flash}"

# ---------- 3) 安装依赖包 ----------
log "安装 glm4v-mcp（视觉 MCP 工具，供模型按需看图）…"
DSH_HOME="$DSH_HOME" dsh plugin --profile "$PROFILE" add glm4v-mcp

log "安装 vision-bridge（图片→GLM-4V 分析→文本，图片不进上游模型）…"
DSH_HOME="$DSH_HOME" dsh plugin --profile "$PROFILE" add "$SCRIPT_DIR/vision-bridge"

if [ "$INSTALL_BROWSER" = "1" ]; then
  log "安装浏览器插件（类 Claude Code 内置浏览器）…"
  DSH_HOME="$DSH_HOME" dsh plugin --profile "$PROFILE" add \
    "@deepseek-ai/dsh-browser-use@0.2.1-rc.2" \
    "@deepseek-ai/dsh-experimental-browser-use-playwright-mcp@0.2.1-rc.2"
fi

# ---------- 4) 写配置（patch 层，只含本仓库相关条目） ----------
MCP_CMD="$PROFILE_DIR/node_modules/.bin/glm4v-mcp"
[ -x "$MCP_CMD" ] || MCP_CMD="$(command -v glm4v-mcp || true)"
[ -n "$MCP_CMD" ] || { warn "未找到 glm4v-mcp 可执行文件，请检查安装"; }

[ -f "$PATCH" ] && cp "$PATCH" "$PATCH.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true

cat > "$PATCH" <<EOF
# dsh-vision-toolkit 生成的配置（$PROFILE profile）
# 模型/上游服务请在 DSH GUI 设置里配置；本文件只含本仓库的视觉相关条目。
# 提示: 想在聊天框粘贴图片，需给对应模型声明 input: [text, image]（GUI 模型设置里）
EOF

if [ "$INSTALL_BROWSER" = "1" ]; then
  cat >> "$PATCH" <<EOF
# ===== 浏览器（可选后端: chrome-devtools 需注释 playwright 段）=====
- insert:
    - id: browser-use
      name: "@deepseek-ai/dsh-browser-use"
    - id: browser-use-playwright
      name: "@deepseek-ai/dsh-experimental-browser-use-playwright-mcp"
      config:
        mode: launch
        headless: true
        executablePath: $CHROME_BIN
EOF
fi

cat >> "$PATCH" <<EOF
# ===== 视觉 MCP 工具（模型按需 analyze_image 看图）=====
- insert:
    - id: mcp-vision
      name: "@deepseek-ai/dsh-mcp-client"
      config:
        serverName: vision
        transport: stdio
        command: $MCP_CMD
        args:
          - --stdio
        env:
          ZHIPU_API_KEY: "$ZHIPU_KEY"
# ===== vision-bridge: 粘贴的图片 → GLM-4V 分析文本 → 只发文本给上游 =====
- insert:
    - id: vision-bridge
      name: "dsh-vision-bridge"
      config:
        apiKey: "$ZHIPU_KEY"
        model: $VISION_MODEL
EOF

log "配置已写入: $PATCH"

# ---------- 5) 收尾 ----------
cat <<EOF

========== 安装完成 ==========
下一步:
  1) 启动 DSH: dsh $PROFILE（或重启已有 GUI / 新建会话，让插件装载生效）
  2) 在 GUI 设置里配置好你的模型（老规矩）
  3) 想让聊天框可粘贴图片: 给模型声明 input: [text, image]

验证视觉功能:
  - 聊天框直接粘贴图片 → 消息会带 [图片分析：…] 文本（图片不上行）
  - 让模型调用 analyze_image 工具看图（浏览器截图、图表、报错弹窗）

注意事项:
  - GLM-4V-Flash 免费但有速率限制；vision-bridge 失败时默认保留原图
  - 图片会发送到智谱云端处理；敏感内容请勿粘贴
  - 浏览器: Chrome 可执行路径可改 $PATCH 中的 executablePath
===========================
EOF
