import runpod
import json
import urllib.request
import urllib.error
import urllib.parse
import base64
import os
import time

# ComfyUI server (run inside the same container as the worker-comfyui base image)
COMFY_URL = "http://127.0.0.1:8188"

# Workflow used for generation. Loaded from the repo so it is baked into the image.
WORKFLOW_PATH = os.path.join(os.path.dirname(__file__), "api-workflow.json")


def _post_json(payload, timeout=600):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{COMFY_URL}/prompt",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def _get_json(url, timeout=600):
    req = urllib.request.Request(url, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def _upload_image(b64_data, name):
    """Upload an input image to ComfyUI's /upload/image endpoint."""
    if "," in b64_data:
        b64_data = b64_data.split(",", 1)[1]
    payload = {"image": b64_data, "overwrite": "true", "name": name}
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{COMFY_URL}/upload/image",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode())


def _wait_for_history(prompt_id, timeout=600):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data = _get_json(f"{COMFY_URL}/history/{prompt_id}")
            if prompt_id in data:
                return data[prompt_id]
        except Exception:
            pass
        time.sleep(2)
    raise TimeoutError(f"Workflow {prompt_id} did not finish in {timeout}s")


def handler(job):
    job_input = job.get("input", {})
    workflow = job_input.get("workflow")

    if workflow is None:
        # No inline workflow: fall back to the baked-in one.
        with open(WORKFLOW_PATH) as f:
            workflow = json.load(f)

    # Upload any provided input images and rewrite LoadImage nodes to use them.
    images = job_input.get("images", [])
    if images:
        for img in images:
            name = img.get("name")
            data = img.get("image")
            if not name or not data:
                continue
            _upload_image(data, name)
            # Point any LoadImage node referencing this filename at the upload.
            for node in workflow.values():
                if node.get("class_type") == "LoadImage":
                    wv = node.get("widgets_values")
                    if isinstance(wv, list) and wv and wv[0] == name:
                        wv[0] = f"{name} [output 0]"

    # Submit the prompt to ComfyUI.
    resp = _post_json({"prompt": workflow, "client_id": "runpod-worker"})
    prompt_id = resp.get("prompt_id")
    if not prompt_id:
        raise RuntimeError(f"ComfyUI did not return a prompt_id: {resp}")

    history = _wait_for_history(prompt_id)

    outputs = []
    for node_id, node_data in history.get("outputs", {}).items():
        for img in node_data.get("images", []):
            # img is like {"filename": "...", "subfolder": "", "type": "output"}
            fname = img.get("filename")
            sub = img.get("subfolder", "")
            itype = img.get("type", "output")
            url = f"{COMFY_URL}/view?filename={urllib.parse.quote(fname)}&subfolder={urllib.parse.quote(sub)}&type={itype}"
            with urllib.request.urlopen(url, timeout=120) as r:
                b64 = base64.b64encode(r.read()).decode()
            outputs.append({
                "filename": fname,
                "type": "base64",
                "data": b64,
            })

    if not outputs:
        raise RuntimeError("ComfyUI finished but produced no images")

    return {"images": outputs}


if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
