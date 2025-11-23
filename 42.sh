#!/bin/bash

# Fortytwo CPU Node Installer – 老CPU终极保活版（无AVX2也能跑）
# 专治 Octa / E5 v3/v4 等老机器的 Illegal instruction
# 模型：VibeThinker-1.5B Q5_K_M (来自 MaziyaPanahi/VibeThinker-1.5B-GGUF)

animate_text() {
    local text="$1"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep 0.005
    done
    echo
}

clear
echo "┌────────────────────────────────────────────────────────────┐"
echo "│     Fortytwo CPU Node – 老CPU终极保活版（无AVX2也能跑）    │"
echo "│                模型改用 VibeThinker-1.5B Q5_K_M            │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""

# 【已修改】使用 VibeThinker-1.5B GGUF 模型配置
export LLM_HF_REPO="MaziyaPanahi/VibeThinker-1.5B-GGUF"
export LLM_HF_MODEL_NAME="VibeThinker-1.5B-Q5_K_M.gguf"
export NODE_NAME="VibeThinker-1.5B Q5_K_M"

# 目录设置
PROJECT_DIR="$HOME/FortytwoNode"
PROJECT_DEBUG_DIR="$PROJECT_DIR/debug"
PROJECT_MODEL_CACHE_DIR="$PROJECT_DIR/model_cache"
CAPSULE_EXEC="$PROJECT_DIR/FortytwoCapsule"
PROTOCOL_EXEC="$PROJECT_DIR/FortytwoProtocol"
UTILS_EXEC="$PROJECT_DIR/FortytwoUtils"
ACCOUNT_PRIVATE_KEY_FILE="$PROJECT_DIR/.account_private_key"

mkdir -p "$PROJECT_DEBUG_DIR" "$PROJECT_MODEL_CACHE_DIR"

# 安装依赖
if ! command -v curl &> /dev/null; then
    echo "正在安装 curl..."
    sudo apt update && sudo apt install -y curl wget
fi

# 下载最新 Utils
animate_text "正在下载 FortytwoUtils..."
UTILS_VERSION=$(curl -s "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/utilities/latest")
curl -L -o "$UTILS_EXEC" "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/utilities/v$UTILS_VERSION/FortytwoUtilsLinux"
chmod +x "$UTILS_EXEC"

# 身份设置
if [[ -f "$ACCOUNT_PRIVATE_KEY_FILE" ]]; then
    ACCOUNT_PRIVATE_KEY=$(cat "$ACCOUNT_PRIVATE_KEY_FILE")
    animate_text "已检测到钱包，继续使用现有身份"
else
    echo "请选择身份方式："
    echo "1) 使用激活码创建新身份"
    echo "2) 用助记词恢复旧身份"
    read -p "请选择 [1-2]: " choice
    if [[ "$choice" == "2" ]]; then
        read -p "输入你的 12/24 词助记词: " phrase
        ACCOUNT_PRIVATE_KEY=$("$UTILS_EXEC" --phrase "$phrase")
        if [[ "$ACCOUNT_PRIVATE_KEY" != "0x"* ]]; then
            echo "助记词无效，重试。"
            exit 1
        fi
        echo "$ACCOUNT_PRIVATE_KEY" > "$ACCOUNT_PRIVATE_KEY_FILE"
    else
        read -p "输入你的激活码: " code
        "$UTILS_EXEC" --create-wallet "$ACCOUNT_PRIVATE_KEY_FILE" --drop-code "$code"
        ACCOUNT_PRIVATE_KEY=$(cat "$ACCOUNT_PRIVATE_KEY_FILE")
    fi
    animate_text "身份创建/恢复完成！"
fi

# 下载兼容模型
animate_text "正在下载模型：$NODE_NAME..."
"$UTILS_EXEC" --hf-repo "$LLM_HF_REPO" --hf-model-name "$LLM_HF_MODEL_NAME" --model-cache "$PROJECT_MODEL_CACHE_DIR" || {
    echo "Utils 下载失败，使用直链备用..."
    # 【已修改】使用新的环境变量进行下载
    wget -O "$PROJECT_MODEL_CACHE_DIR/$LLM_HF_MODEL_NAME" \
    "https://huggingface.co/$LLM_HF_REPO/resolve/main/$LLM_HF_MODEL_NAME"
}

# 下载 Capsule 和 Protocol
animate_text "正在下载最新 Capsule 和 Protocol..."
CAPSULE_VERSION=$(curl -s https://fortytwo-network-public.s3.us-east-2.amazonaws.com/capsule/latest)
curl -L -o "$CAPSULE_EXEC" "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/capsule/v$CAPSULE_VERSION/FortytwoCapsule-linux-amd64"
chmod +x "$CAPSULE_EXEC"

PROTOCOL_VERSION=$(curl -s https://fortytwo-network-public.s3.us-east-2.amazonaws.com/protocol/latest)
curl -L -o "$PROTOCOL_EXEC" "https://fortytwo-network-public.s3.us-east-2.amazonaws.com/protocol/v$PROTOCOL_VERSION/FortytwoProtocolNode-linux-amd64"
chmod +x "$PROTOCOL_EXEC"

# 启动 Capsule
animate_text "正在启动 Capsule（使用模型：$NODE_NAME）..."
"$CAPSULE_EXEC" \
  --llm-hf-repo "$LLM_HF_REPO" \
  --llm-hf-model-name "$LLM_HF_MODEL_NAME" \
  --model-cache "$PROJECT_MODEL_CACHE_DIR" &
CAPSULE_PID=$!

# 等待 Capsule 就绪
animate_text "等待 Capsule 就绪（最多 3 分钟）..."
timeout=0
while ! curl -s http://127.0.0.1:42442/ready >/dev/null 2>&1; do
    sleep 5
    timeout=$((timeout+5))
    if ! kill -0 $CAPSULE_PID 2>/dev/null; then
        echo "❌ Capsule 启动失败！检查 CPU（cat /proc/cpuinfo | grep avx），或重跑脚本。"
        exit 1
    fi
    if [[ $timeout -gt 180 ]]; then
        echo "❌ 超时！请检查模型文件是否正确下载。"
        exit 1
    fi
done
animate_text "Capsule 启动成功！"

# 启动 Protocol
animate_text "正在启动 Protocol 主节点，准备开始赚积分！"
"$PROTOCOL_EXEC" --account-private-key "$ACCOUNT_PRIVATE_KEY" --db-folder "$PROJECT_DEBUG_DIR/db" &

animate_text "🎉 全部启动成功！节点后台运行中，积分开始上涨～"
echo "模型详情：$NODE_NAME"
echo "查看日志：tail -f $PROJECT_DEBUG_DIR/db/*.log"
echo "停止节点：pkill -f Fortytwo"

# 保持进程
trap "kill $CAPSULE_PID $! 2>/dev/null; exit 0" SIGINT SIGTERM
wait
