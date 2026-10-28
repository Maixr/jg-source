"""通过 HTTP Range 只取 .tpz 里需要的那几个模板文件。
单连接被限速，所以把每个文件切成 1MB 小块，多路并行拉取后拼装。"""
import os
import struct
import sys
import time
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor

URL = os.environ.get(
    "TPL_URL",
    "https://github.com/godotengine/godot/releases/download/"
    "4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz")
OUT_DIR = os.path.expandvars(r"%APPDATA%\Godot\export_templates\4.7.2.stable")

CHUNK = 512 * 1024
WORKERS = 16


def fetch_range(start, end, tries=8):
    last = None
    want = end - start + 1
    for attempt in range(tries):
        try:
            req = urllib.request.Request(URL)
            req.add_header("Range", "bytes=%d-%d" % (start, end))
            with urllib.request.urlopen(req, timeout=100) as resp:
                data = resp.read()
            if len(data) == want:
                return data
            last = "short read %d/%d" % (len(data), want)
        except Exception as exc:  # noqa: BLE001
            last = repr(exc)[:120]
        time.sleep(1.0 + attempt)
    raise RuntimeError("range %d-%d failed: %s" % (start, end, last))


def total_size():
    req = urllib.request.Request(URL)
    req.add_header("Range", "bytes=0-0")
    with urllib.request.urlopen(req, timeout=120) as resp:
        return int(resp.headers["Content-Range"].split("/")[1])


def read_central_directory():
    size = total_size()
    tail_len = min(size, 133120)
    tail = fetch_range(size - tail_len, size - 1)
    pos = tail.rfind(b"PK\x05\x06")
    if pos < 0:
        raise RuntimeError("no EOCD")
    (_s, _d0, _d1, _n0, count, cd_size, cd_off, _cmt) = struct.unpack(
        "<IHHHHIIH", tail[pos:pos + 22])
    if cd_off == 0xFFFFFFFF or cd_size == 0xFFFFFFFF or count == 0xFFFF:
        loc = tail.rfind(b"PK\x06\x07", 0, pos)
        eocd64_off = struct.unpack("<Q", tail[loc + 8:loc + 16])[0]
        rec = fetch_range(eocd64_off, eocd64_off + 55)
        count = struct.unpack("<Q", rec[32:40])[0]
        cd_size = struct.unpack("<Q", rec[40:48])[0]
        cd_off = struct.unpack("<Q", rec[48:56])[0]
    cd = fetch_range(cd_off, cd_off + cd_size - 1)

    entries = []
    i = 0
    while i + 46 <= len(cd) and cd[i:i + 4] == b"PK\x01\x02":
        method = struct.unpack("<H", cd[i + 10:i + 12])[0]
        csize, usize = struct.unpack("<II", cd[i + 20:i + 28])
        fnlen, extralen, cmtlen = struct.unpack("<HHH", cd[i + 28:i + 34])
        off = struct.unpack("<I", cd[i + 42:i + 46])[0]
        name = cd[i + 46:i + 46 + fnlen].decode("utf-8", "replace")
        extra = cd[i + 46 + fnlen:i + 46 + fnlen + extralen]
        j = 0
        while j + 4 <= len(extra):
            hid, hsize = struct.unpack("<HH", extra[j:j + 4])
            if hid == 0x0001:
                body = extra[j + 4:j + 4 + hsize]
                k = 0
                if usize == 0xFFFFFFFF:
                    usize = struct.unpack("<Q", body[k:k + 8])[0]
                    k += 8
                if csize == 0xFFFFFFFF:
                    csize = struct.unpack("<Q", body[k:k + 8])[0]
                    k += 8
                if off == 0xFFFFFFFF:
                    off = struct.unpack("<Q", body[k:k + 8])[0]
            j += 4 + hsize
        entries.append({"name": name, "method": method, "csize": csize,
                        "usize": usize, "off": off})
        i += 46 + fnlen + extralen + cmtlen
    return size, entries


def data_offset(entry):
    head = fetch_range(entry["off"], entry["off"] + 29)
    if head[:4] != b"PK\x03\x04":
        raise RuntimeError("bad local header for " + entry["name"])
    fnlen, extralen = struct.unpack("<HH", head[26:30])
    return entry["off"] + 30 + fnlen + extralen


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    size, entries = read_central_directory()
    print("archive %.1f MB, %d entries" % (size / 1048576.0, len(entries)), flush=True)
    if mode == "list":
        for e in entries:
            print("%10.2f MB  %s" % (e["usize"] / 1048576.0, e["name"]))
        return

    patterns = sys.argv[2:]
    picked = [e for e in entries
              if e["name"].startswith("templates/")
              and any(p in e["name"] for p in patterns)]
    if not picked:
        print("nothing matched", patterns)
        return
    print("files: %s" % ", ".join(e["name"] for e in picked), flush=True)

    tasks = []  # (entry_idx, chunk_idx, start, end)
    for idx, e in enumerate(picked):
        base = data_offset(e)
        e["base"] = base
        if e["csize"] == 0:
            continue
        n = (e["csize"] + CHUNK - 1) // CHUNK
        for c in range(n):
            s = base + c * CHUNK
            en = min(s + CHUNK, base + e["csize"]) - 1
            tasks.append((idx, c, s, en))
    total_mb = sum(e["csize"] for e in picked) / 1048576.0
    print("chunks: %d (%.1f MB, %d workers)" % (len(tasks), total_mb, WORKERS), flush=True)

    started = time.time()
    results = {}
    done = [0]

    def work(t):
        idx, c, s, en = t
        blob = fetch_range(s, en)
        results[(idx, c)] = blob
        done[0] += 1
        if done[0] % 4 == 0 or done[0] == len(tasks):
            print("  %d/%d chunks, %.0fs" % (done[0], len(tasks), time.time() - started),
                  flush=True)

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        list(pool.map(work, tasks))

    os.makedirs(OUT_DIR, exist_ok=True)
    for idx, e in enumerate(picked):
        if e["csize"] == 0:
            raw = b""
        else:
            n = (e["csize"] + CHUNK - 1) // CHUNK
            raw = b"".join(results[(idx, c)] for c in range(n))
        blob = zlib.decompress(raw, -15) if e["method"] == 8 else raw
        rel = e["name"][len("templates/"):]
        dest = os.path.join(OUT_DIR, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dest) or OUT_DIR, exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(blob)
        print("  ok %-42s %6.2f MB" % (rel, len(blob) / 1048576.0), flush=True)
    print("done in %.0fs -> %s" % (time.time() - started, OUT_DIR), flush=True)


if __name__ == "__main__":
    main()
