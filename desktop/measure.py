import json
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import time

CLOUDFLARE_DOWNLOAD_SIZE = 8_000_000
SELECTEL_DOWNLOAD_SIZE = 24 * 1024 * 1024
UPLOAD_SIZE = 8_000_000
SERVERS = (
    (
        "Cloudflare",
        "https://speed.cloudflare.com/__down?bytes=0",
        f"https://speed.cloudflare.com/__down?bytes={CLOUDFLARE_DOWNLOAD_SIZE}",
        "https://speed.cloudflare.com/__up",
        CLOUDFLARE_DOWNLOAD_SIZE,
    ),
    (
        "Selectel",
        "https://speedtest.selectel.ru/empty.php",
        "https://speedtest.selectel.ru/garbage.php?ckSize=24",
        "https://speedtest.selectel.ru/empty.php",
        SELECTEL_DOWNLOAD_SIZE,
    ),
)


def measure_latency(url):
    command = [
        "curl", "--disable", "--fail", "--silent", "--show-error",
        "--connect-timeout", "3", "--max-time", "5",
        "--output", "/dev/null", "--write-out",
        "%{http_code} %{time_pretransfer} %{time_starttransfer}",
    ]
    output = subprocess.run(
        command + [url], capture_output=True, check=True,
    ).stdout
    status, ready, first_byte = map(float, output.split())
    if not 200 <= status < 300:
        raise ValueError("Latency probe rejected")
    return max(0, first_byte - ready) * 1000


def transfer(url, phase, size):
    field = "download" if phase == "down" else "upload"
    command = [
        "curl", "--disable", "--fail", "--progress-bar", "--show-error",
        "--connect-timeout", "3", "--max-time", "20", "--output", "/dev/null",
        "--write-out", f"%{{http_code}} %{{size_{field}}} %{{speed_{field}}}",
    ]
    with tempfile.TemporaryFile() as payload:
        if phase == "up":
            payload.truncate(size)
            command += ["--data-binary", "@-"]
        with subprocess.Popen(
            command + [url], stdin=payload,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ) as curl:
            try:
                report_progress(curl.stderr, phase, size)
                output = curl.stdout.read()
                if curl.wait() != 0:
                    raise ValueError("Transfer failed")
            finally:
                if curl.poll() is None:
                    curl.kill()
    status, transferred, speed = map(float, output.split())
    if not 200 <= status < 300 or transferred != size or speed <= 0:
        raise ValueError("Incomplete transfer")
    mbps = speed * 8 / 1_000_000
    print(json.dumps({"phase": phase, "mbps": mbps}), flush=True)
    return mbps


def report_progress(stream, phase, size):
    previous = None
    pending = b""
    while chunk := stream.read1(4096):
        records = (pending + chunk).replace(b"\r", b"\n").split(b"\n")
        pending = records.pop()
        for record in records:
            match = re.search(rb"(\d+\.\d+)%\s*$", record)
            if not match:
                continue
            percent = float(match[1])
            now = time.monotonic()
            if previous is None:
                previous = (now, percent)
                continue
            elapsed = now - previous[0]
            if elapsed >= 0.09 and previous[1] < percent < 100:
                mbps = (percent - previous[1]) * size * 8 / (100_000_000 * elapsed)
                print(json.dumps({"phase": phase, "mbps": mbps}), flush=True)
                previous = (now, percent)


def fresh_url(url):
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}r={time.time_ns()}"


def run():
    for name, ping_url, download_url, upload_url, download_size in SERVERS:
        print(json.dumps({"server": name}), flush=True)
        try:
            latency = statistics.median(
                measure_latency(fresh_url(ping_url)) for _ in range(3)
            )
            down = transfer(fresh_url(download_url), "down", download_size)
            upload = transfer(upload_url, "up", UPLOAD_SIZE)
            return {"down": down, "up": upload, "latency": latency, "server": name}
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f"{name}: {error}", file=sys.stderr)
    raise ValueError("All speed test servers failed")


def stop(_signal, _frame):
    # Unwind the subprocess context so it terminates any active curl request.
    raise SystemExit(130)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    try:
        print(json.dumps({"result": run()}), flush=True)
    except (OSError, ValueError, subprocess.CalledProcessError):
        raise SystemExit(1)
