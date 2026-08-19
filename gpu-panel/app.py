"""
Super Sistema — GPU Panel (Tesla P100)
Одна кнопка → всё запускается само.
Порт: 8765
"""

import asyncio
import json
import os
import subprocess
from datetime import datetime
from typing import AsyncGenerator

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.templating import Jinja2Templates

app = FastAPI(title="Super Sistema GPU Panel")
templates = Jinja2Templates(directory="templates")

OLLAMA_URL    = os.getenv("OLLAMA_URL", "http://ollama:11434")
# Bind mount из /tmp/super-sistema/shared на хосте в /shared в контейнере.
# setup-tesla-p100.sh пишет прогресс сюда, watch-gpu.sh читает триггер отсюда.
SHARED_DIR    = os.getenv("SHARED_DIR", "/shared")
TRIGGER_FILE  = os.path.join(SHARED_DIR, "gpu-setup-trigger")
PROGRESS_FILE = os.path.join(SHARED_DIR, "progress.log")


# ─── Утилиты ─────────────────────────────────────────────────────────────────

def run_cmd(cmd: list[str], timeout: int = 5) -> tuple[bool, str]:
    """Запустить команду. Возвращает (успех, вывод)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode == 0, (r.stdout + r.stderr).strip()
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return False, str(e)


def get_gpu_info() -> dict:
    """Получить данные GPU через nvidia-smi."""
    ok, raw = run_cmd([
        "nvidia-smi",
        "--query-gpu=name,memory.total,memory.used,memory.free,"
        "utilization.gpu,temperature.gpu,power.draw,driver_version",
        "--format=csv,noheader,nounits",
    ])
    if not ok:
        return {"available": False, "error": "nvidia-smi не найден или GPU не подключена"}

    gpus = []
    for line in raw.strip().split("\n"):
        if not line.strip():
            continue
        p = [x.strip() for x in line.split(",")]
        if len(p) < 8:
            continue
        mem_total = int(p[1]) if p[1].isdigit() else 0
        mem_used  = int(p[2]) if p[2].isdigit() else 0
        gpus.append({
            "name":         p[0],
            "mem_total_mb": mem_total,
            "mem_used_mb":  mem_used,
            "mem_free_mb":  int(p[3]) if p[3].isdigit() else 0,
            "mem_pct":      round(mem_used / mem_total * 100, 1) if mem_total else 0,
            "utilization":  p[4],
            "temperature":  p[5],
            "power_draw":   p[6],
            "driver":       p[7],
        })
    return {"available": bool(gpus), "gpus": gpus}


def get_pcie_nvidia() -> list[str]:
    """Список NVIDIA/Tesla устройств из lspci."""
    ok, raw = run_cmd(["lspci"])
    if not ok:
        return []
    return [l for l in raw.splitlines()
            if "nvidia" in l.lower() or "tesla" in l.lower()]


async def get_ollama_info() -> dict:
    """Проверить статус Ollama."""
    try:
        async with httpx.AsyncClient(timeout=3.0) as c:
            r = await c.get(f"{OLLAMA_URL}/api/tags")
            if r.status_code == 200:
                models = [m["name"] for m in r.json().get("models", [])]
                return {"running": True, "models": models}
    except Exception:
        pass
    return {"running": False, "models": []}


def read_progress_lines(since_line: int = 0) -> list[dict]:
    """Прочитать строки прогресса начиная с since_line."""
    if not os.path.exists(PROGRESS_FILE):
        return []
    try:
        with open(PROGRESS_FILE, encoding="utf-8") as f:
            lines = f.readlines()
        result = []
        for raw in lines[since_line:]:
            raw = raw.strip()
            if not raw:
                continue
            parts = raw.split("|", 2)
            if len(parts) == 3:
                result.append({"level": parts[0], "time": parts[1], "msg": parts[2]})
            else:
                result.append({"level": "INFO", "time": "", "msg": raw})
        return result
    except Exception:
        return []


def is_setup_done() -> bool:
    """Вернуть True если в логе уже есть строка DONE."""
    return any(l["level"] == "DONE" for l in read_progress_lines(0))


# ─── HTTP endpoints ──────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
async def root(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(request=request, name="index.html")


@app.get("/api/status")
async def api_status() -> JSONResponse:
    """Полный статус: GPU, Ollama, PCIe, флаги."""
    gpu    = get_gpu_info()
    ollama = await get_ollama_info()
    pcie   = get_pcie_nvidia()
    return JSONResponse({
        "ts":      datetime.now().isoformat(),
        "gpu":     gpu,
        "ollama":  ollama,
        "pcie":    pcie,
        "running": os.path.exists(TRIGGER_FILE),
        "done":    is_setup_done(),
    })


@app.post("/api/activate")
async def api_activate() -> JSONResponse:
    """Нажатие кнопки ВКЛЮЧИТЬ P100 — создаёт триггер для watch-gpu.sh."""
    try:
        os.makedirs(SHARED_DIR, exist_ok=True)
        # Очистить старый лог прогресса
        with open(PROGRESS_FILE, "w", encoding="utf-8") as f:
            f.write(
                f"INFO|{datetime.now().strftime('%H:%M:%S')}"
                f"|Запрос на активацию Tesla P100 отправлен\n"
            )
        # Создать файл-триггер — watch-gpu.sh его увидит и запустит установку
        with open(TRIGGER_FILE, "w", encoding="utf-8") as f:
            f.write(datetime.now().isoformat())
        return JSONResponse({"ok": True})
    except Exception as e:
        return JSONResponse({"ok": False, "error": str(e)}, status_code=500)


@app.get("/api/progress")
async def api_progress(since: int = 0) -> JSONResponse:
    """JSON с новыми строками прогресса начиная с позиции since."""
    lines = read_progress_lines(since)
    total = since + len(lines)          # FIX: корректный счётчик позиции
    done  = is_setup_done()
    return JSONResponse({"lines": lines, "total": total, "done": done})


@app.get("/stream/gpu")
async def stream_gpu() -> StreamingResponse:
    """SSE: статус GPU, Ollama, PCIe — обновляется каждые 3 сек."""
    async def gen() -> AsyncGenerator[str, None]:
        while True:
            payload = json.dumps({
                "ts":     datetime.now().strftime("%H:%M:%S"),
                "gpu":    get_gpu_info(),
                "ollama": await get_ollama_info(),
                "pcie":   get_pcie_nvidia(),
            }, ensure_ascii=False)
            yield f"data: {payload}\n\n"
            await asyncio.sleep(3)

    return StreamingResponse(
        gen(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/stream/progress")
async def stream_progress() -> StreamingResponse:
    """SSE: прогресс установки в реальном времени (читает progress.log)."""
    async def gen() -> AsyncGenerator[str, None]:
        sent = 0
        while True:
            new_lines = read_progress_lines(sent)
            if new_lines:
                sent += len(new_lines)
                yield f"data: {json.dumps({'lines': new_lines, 'sent': sent}, ensure_ascii=False)}\n\n"

            # Завершить стрим когда установка закончена
            if is_setup_done():
                yield 'data: {"done": true}\n\n'
                return

            await asyncio.sleep(1)

    return StreamingResponse(
        gen(), media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app:app", host="0.0.0.0", port=8765, reload=False)
