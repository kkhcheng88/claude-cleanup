#!/usr/bin/env python3
"""proxy-logger.py - prove whether a program actually honours proxy settings.

WHY THIS EXISTS
  When TUN is off, only the programs that are configured for the proxy go through
  Clash. A program that ignores proxy settings keeps working normally, so nothing in
  the mihomo log or in Clash Verge's connection list can reveal it - the absence of
  evidence looks identical to "no traffic". This script turns that silence into a
  measurement: point a program at this logger. If the program appears in the log, it
  honours proxy settings; if the program still works but the log stays empty, it
  bypasses the proxy entirely and would leak your real IP.

  The logger never forwards anything. It records the target and then answers
  "502 Bad Gateway", so a request through it fails on purpose - the only thing being
  measured is whether the program tried to use the proxy at all.

USAGE
  1. Keep Clash Verge running (so the rest of the machine is unaffected).
  2. Start the logger:
       python proxy-logger.py                 # listens on 127.0.0.1:8899
       python proxy-logger.py --port 9000
  3. Point ONE program at it, e.g.
       - environment:  set HTTPS_PROXY=http://127.0.0.1:8899   (then start the app)
       - browser:      set the system/browser proxy to 127.0.0.1:8899
  4. Use the program normally (open the AI service, send one message).
  5. Read proxy-hosts.log next to this script:
       lines present  -> the program honours proxy settings (configuring it works)
       file empty     -> the program ignores proxy settings (it will leak real-IP
                         traffic unless TUN or a system-wide capture covers it)
  6. Restore the program's proxy setting, or stop the logger with Ctrl+C.

OBSERVED ENTRIES LOOK LIKE
  2026-10-07 02:30:11  CONNECT  api.anthropic.com:443      from 127.0.0.1:52413
  2026-10-07 02:30:14  GET      http://example.com/         from 127.0.0.1:52420
"""
import argparse
import datetime
import pathlib
import socket
import threading

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_LOG = HERE / "proxy-hosts.log"
_lock = threading.Lock()


def log(line: str, log_path: pathlib.Path) -> None:
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with _lock:
        with log_path.open("a", encoding="utf-8") as fh:
            fh.write(f"{stamp}  {line}\n")


def handle(conn: socket.socket, addr, log_path: pathlib.Path) -> None:
    try:
        conn.settimeout(10)
        data = conn.recv(8192)
        if not data:
            return
        first = data.split(b"\r\n", 1)[0].decode("latin-1", "replace")
        parts = first.split()
        if len(parts) >= 2 and parts[0].upper() == "CONNECT":
            log(f"CONNECT  {parts[1]:<40} from {addr[0]}:{addr[1]}", log_path)
        else:
            log(f"{parts[0].upper():<8} {parts[1] if len(parts) > 1 else '?':<40} from {addr[0]}:{addr[1]}", log_path)
        # never forward: the caller must see a failure, we only want the evidence
        conn.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    except Exception as exc:  # noqa: BLE001 - diagnostics tool
        log(f"ERROR    {exc}", log_path)
    finally:
        try:
            conn.close()
        except Exception:  # noqa: BLE001
            pass


def main() -> None:
    ap = argparse.ArgumentParser(description="Log-only proxy for checking proxy honouring.")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--log", default=str(DEFAULT_LOG))
    args = ap.parse_args()
    log_path = pathlib.Path(args.log)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(64)

    print(f"proxy-logger listening on {args.host}:{args.port}")
    print(f"recording to {log_path}")
    print("nothing is forwarded - requests through it fail on purpose (HTTP 502)")
    print("Ctrl+C to stop")
    try:
        while True:
            conn, addr = srv.accept()
            threading.Thread(target=handle, args=(conn, addr, log_path), daemon=True).start()
    except KeyboardInterrupt:
        print("\nstopped")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
