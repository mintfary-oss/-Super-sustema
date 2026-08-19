"""
Super Sistema — GPU Status Panel
Веб-панель для мониторинга Tesla P100 и управления GPU в Ollama.
Работает на порту 8765.
"""

import asyncio
import json
import subprocess
import os
import time
import re
from datetime import datetime
from typing import AsyncGenerator

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.templating import Jinja2Templates

app = FastAPI(title="Super Sistema — GPU Panel")
templates = Jinja2Templates(directory="templates")

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
TRIGGER_FILE = "/shared/gpu-setup-trigger"  # Флаг для host-скрипта


def run_cmd(cmd: list[str], timeout: int = 5) -> tuple[bool, str]:
    """Запустить команду и вернуть (успех, вывод)."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode == 0, (result.stdout + result.stderr).strip()
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, str(e)


def get_nvidia_smi_data() -> dict:
    """Получить данные о GPU через nvidia-smi."""
    ok, raw = run_cmd([
        "nvidia-smi",
        "--query-gpu=name,memory.total,memory.used,memory.free,"
        "utilization.gpu,temperature.gpu,power.draw,driver_version",
        "--format=csv,noheader,nounits"
    ])
    if not ok:
        return {"available": False, "error": raw or "nvidia-smi not found"}

    gpus = []
    for line in raw.strip().split("\n"):
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 8:
            mem_total = int(parts[1]) if parts[1].isdigit() else 0
            mem_used  = int(parts[2]) if parts[2].isdigit() else 0
            gpus.append({
                "name":          parts[0],
                "mem_total_mb":  mem_total,
                "mem_used_mb":   mem_used,
                "mem_free_mb":   int(parts[3]) if parts[3].isdigit() else 0,
                "mem_pct":       round(mem_used / mem_total * 100, 1) if mem_total > 0 else 0,
                "utilization":   parts[4],
                "temperature":   parts[5],
                "power_draw":    parts[6],
                "driver":        parts[7],
            })

    return {"available": True, "gpus": gpus, "count": len(gpus)}


def get_gpu_processes() -> list[dict]:
    """Получить процессы использующие GPU."""
    ok, raw = run_cmd([
        "nvidia-smi",
        "--query-compute-apps=pid,name,used_memory",
        "--format=csv,noheader,nounits"
    ])
    if not ok or not raw.strip():
        return []

    procs = []
    for line in raw.strip().split("\n"):
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 3:
            procs.append({"pid": parts[0], "name": parts[1], "memory_mb": parts[2]})
    return procs


async def get_ollama_status() -> dict:
    """Проверить статус Ollama и использование GPU."""
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(f"{OLLAMA_URL}/api/tags")
            if resp.status_code == 200:
                data = resp.json()
                models = [m["name"] for m in data.get("models", [])]
                return {"running": True, "models": models, "model_count": len(models)}
    except Exception:
        pass
    return {"running": False, "models": [], "model_count": 0}


def get_pcie_devices() -> list[str]:
    """Список NVIDIA устройств через lspci."""
    ok, raw = run_cmd(["lspci"])
    if not ok:
        return []
    return [line for line in raw.split("\n") if "nvidia" in line.lower()]


@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Главная страница — дашборд GPU."""
    return templates.TemplateResponse(request=request, name="index.html")


@app.get("/api/status")
async def api_status():
    """JSON статус: GPU, Ollama, PCIe устройства."""
    gpu_data   = get_nvidia_smi_data()
    ollama     = await get_ollama_status()
    processes  = get_gpu_processes()
    pcie       = get_pcie_devices()
    trigger_pending = os.path.exists(TRIGGER_FILE)

    return JSONResponse({
        "timestamp":       datetime.now().isoformat(),
        "gpu":             gpu_data,
        "ollama":          ollama,
        "gpu_processes":   processes,
        "pcie_devices":    pcie,
        "trigger_pending": trigger_pending,
    })


@app.get("/api/smi-full")
async def api_smi_full():
    """Полный вывод nvidia-smi."""
    ok, raw = run_cmd(["nvidia-smi"], timeout=10)
    return JSONResponse({"ok": ok, "output": raw})


@app.post("/api/trigger-setup")
async def trigger_setup():
    """
    Создать файл-триггер для host-скрипта watch-gpu.sh.
    Host-скрипт отслеживает этот файл и запускает setup-tesla-p100.sh.
    """
    try:
        os.makedirs(os.path.dirname(TRIGGER_FILE), exist_ok=True)
        with open(TRIGGER_FILE, "w") as f:
            f.write(datetime.now().isoformat())
        return JSONResponse({
            "ok": True,
            "message": "Запрос на активацию GPU отправлен. "
                       "watch-gpu.sh запустит setup-tesla-p100.sh на хосте."
        })
    except Exception as e:
        return JSONResponse({"ok": False, "message": str(e)}, status_code=500)


@app.get("/stream")
async def sse_stream():
    """
    Server-Sent Events — обновления статуса в реальном времени.
    Используется для автообновления дашборда каждые 3 сек.
    """
    async def event_generator() -> AsyncGenerator[str, None]:
        while True:
            gpu_data  = get_nvidia_smi_data()
            ollama    = await get_ollama_status()
            processes = get_gpu_processes()

            payload = json.dumps({
                "ts":        datetime.now().strftime("%H:%M:%S"),
                "gpu":       gpu_data,
                "ollama":    ollama,
                "processes": processes,
            }, ensure_ascii=False)

            yield f"data: {payload}\n\n"
            await asyncio.sleep(3)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control":               "no-cache",
            "X-Accel-Buffering":           "no",
            "Access-Control-Allow-Origin": "*",
        },
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8765, reload=False)
