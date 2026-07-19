#!/usr/bin/env bash

# Start SSH server if PUBLIC_KEY is set
if [ -n "$PUBLIC_KEY" ]; then
  mkdir -p ~/.ssh
  echo "$PUBLIC_KEY" > ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  for key_type in rsa ecdsa ed25519; do
    key_file="/etc/ssh/ssh_host_${key_type}_key"
    if [ ! -f "$key_file" ]; then
      ssh-keygen -t "$key_type" -f "$key_file" -q -N ''
    fi
  done
  service ssh start && echo "worker-comfyui: SSH server started" || echo "worker-comfyui: SSH server could not be started" >&2
fi

TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

echo "worker-comfyui: Checking GPU availability..."
if ! GPU_CHECK=$(python3 -c "
import torch
try:
  torch.cuda.init()
  name = torch.cuda.get_device_name(0)
  cap = torch.cuda.get_device_capability(0)
  _ = (torch.zeros(8, device='cuda') + 1).sum().item()
  torch.cuda.synchronize()
  print(f'OK: {name} (sm_{cap[0]}{cap[1]}), torch {torch.__version__}, cuda {torch.version.cuda}')
except Exception as e:
  print(f'FAIL: {e}')
  exit(1)
" 2>&1); then
  echo "worker-comfyui: GPU is not available or incompatible: $GPU_CHECK"
  exit 1
fi
echo "worker-comfyui: GPU available — $GPU_CHECK"

comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

: "${COMFY_LOG_LEVEL:=DEBUG}"

COMFY_PID_FILE="/tmp/comfyui.pid"

if [ "$SERVE_API_LOCALLY" == "true" ]; then
  python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
  echo $! > "$COMFY_PID_FILE"
  echo "worker-comfyui: Starting RunPod Handler"
  python -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
  python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
  echo $! > "$COMFY_PID_FILE"
  echo "worker-comfyui: Starting RunPod Handler"
  python -u /rp_handler.py
fi
