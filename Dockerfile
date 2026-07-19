# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.8.4-base

# install custom nodes into comfyui
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper /comfyui/custom_nodes/ComfyUI-WanVideoWrapper && cd /comfyui/custom_nodes/ComfyUI-WanVideoWrapper && (git checkout d9b1f4d1a5aea91d101ae97a54714a5861af3f50 2>/dev/null || (git fetch origin d9b1f4d1a5aea91d101ae97a54714a5861af3f50 --depth=1 && git checkout d9b1f4d1a5aea91d101ae97a54714a5861af3f50) || echo "WARN: commit d9b1f4d1a5aea91d101ae97a54714a5861af3f50 unreachable, falling back to default branch HEAD")
RUN comfy node install --exit-on-fail comfyui-wanvideowrapper@1.3.9 --mode remote || (echo "WARN: comfyui-wanvideowrapper@1.3.9 unavailable, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-wanvideowrapper --mode remote)
RUN git clone https://github.com/kijai/ComfyUI-KJNodes /comfyui/custom_nodes/ComfyUI-KJNodes && cd /comfyui/custom_nodes/ComfyUI-KJNodes && (git checkout a6b867b63a29ca48ddb15c589e17a9f2d8530d57 2>/dev/null || (git fetch origin a6b867b63a29ca48ddb15c589e17a9f2d8530d57 --depth=1 && git checkout a6b867b63a29ca48ddb15c589e17a9f2d8530d57) || echo "WARN: commit a6b867b63a29ca48ddb15c589e17a9f2d8530d57 unreachable, falling back to default branch HEAD")
RUN comfy node install --exit-on-fail comfyui-custom-scripts@1.2.5 || (echo "WARN: comfyui-custom-scripts@1.2.5 unavailable, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-custom-scripts)
RUN comfy node install --exit-on-fail comfyui-videohelpersuite@1.7.9 || (echo "WARN: comfyui-videohelpersuite@1.7.9 unavailable, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-videohelpersuite)
RUN comfy node install --exit-on-fail comfyui-easy-use@1.3.4 || (echo "WARN: comfyui-easy-use@1.3.4 unavailable, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-easy-use)

# Models are already baked into the Network Volume (mounted at /runpod-volume).
# Map /runpod-volume into ComfyUI's model search paths.
ADD extra_model_paths.yaml /comfyui/extra_model_paths.yaml

# Serverless handler + startup script (from runpod-workers/worker-comfyui)
ADD handler.py /handler.py
ADD start.sh /start.sh
RUN chmod +x /start.sh

# Default command: start ComfyUI and the RunPod handler
CMD ["/start.sh"]
