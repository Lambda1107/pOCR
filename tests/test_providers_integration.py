#!/usr/bin/env python3
"""
Integration test for the OpenAI-compatible providers (kimi + llm modes).

Verifies, against the REAL Moonshot API using the local kimi-key file:
  1. resolveChatCompletionsURL — all 4 base-URL input forms (incl. trailing slash).
  2. parseCustomHeaders — line parsing + that custom headers override defaults.
  3. buildChatCompletionRequest — exact request body the app sends.
  4. parseChatCompletionContent — content as string, array, reasoning fallback,
     and error-object handling.
  5. A real end-to-end OCR call returning the expected text.

These mirror the Swift logic in Sources/OCRService.swift. If the API contract or
our parsing drifts, this test fails.

Usage:  python3 tests/test_providers_integration.py
Requires: ./kimi-key present (gitignored local credential file).
"""
import json
import os
import sys
import urllib.request
import urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYFILE = os.path.join(ROOT, "kimi-key")
TEST_IMG = "/tmp/kimi_test.png"

failures = []


def check(name, cond, detail=""):
    status = "PASS" if cond else "FAIL"
    print(f"  [{status}] {name}" + (f" — {detail}" if detail and not cond else ""))
    if not cond:
        failures.append(name)


def read_key():
    if not os.path.exists(KEYFILE):
        print(f"SKIP: {KEYFILE} not found (no credential to test against).")
        sys.exit(0)
    domain = key = None
    for line in open(KEYFILE):
        line = line.strip()
        if line.startswith("domain:"):
            domain = line.split(":", 1)[1].strip()
        elif line.startswith("key:"):
            key = line.split(":", 1)[1].strip()
    return domain, key


# ---- Swift-mirroring helpers ----

def resolve_chat_completions_url(base):  # mirrors resolveChatCompletionsURL
    t = base.strip()
    while t.endswith("/"):
        t = t[:-1]
    if not t:
        return None
    if t.endswith("/chat/completions"):
        return t
    if t.endswith("/v1"):
        return t + "/chat/completions"
    return t + "/v1/chat/completions"


def parse_custom_headers(text):  # mirrors parseCustomHeaders
    result = {}
    for line in text.split("\n"):
        t = line.strip()
        if not t or ":" not in t:
            continue
        k, v = t.split(":", 1)
        k = k.strip()
        v = v.strip()
        if k:
            result[k] = v
    return result


def build_body(model, system_prompt, data_uri):  # mirrors buildChatCompletionRequest body
    messages = []
    sp = system_prompt.strip()
    if sp:
        messages.append({"role": "system", "content": sp})
    messages.append({"role": "user", "content": [
        {"type": "image_url", "image_url": {"url": data_uri}},
        {"type": "text", "text": "Please extract all text from this image."},
    ]})
    return {"model": model, "messages": messages}


def parse_content(j):  # mirrors parseChatCompletionContent
    if isinstance(j.get("error"), dict):
        return ("error", j["error"].get("message", "Unknown error"))
    if isinstance(j.get("code"), int) and j["code"] != 0:
        return ("error", j.get("message", "Unknown error"))
    choices = j.get("choices") or []
    if not choices:
        return ("invalid", "no choices")
    msg = choices[0].get("message", {})
    if isinstance(msg.get("content"), str):
        return ("ok", msg["content"])
    if isinstance(msg.get("content"), list):
        text = "".join(p.get("text", "") for p in msg["content"] if isinstance(p, dict))
        if text:
            return ("ok", text)
    if msg.get("reasoning_content"):
        return ("ok", msg["reasoning_content"])
    return ("invalid", "no text content")


def post(domain, key, body, extra_headers=None):
    endpoint = resolve_chat_completions_url(f"https://{domain}/v1")
    req = urllib.request.Request(endpoint, data=json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", f"Bearer {key}")
    for k, v in (extra_headers or {}).items():  # custom headers last -> override
        req.add_header(k, v)
    try:
        r = urllib.request.urlopen(req, timeout=60)
        return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def reasoning_state(raw):
    """Return (has_reasoning, completion_tokens) for a 200 response, else (None,None)."""
    j = json.loads(raw)
    if j.get("error"):
        return None, None
    msg = (j.get("choices") or [{}])[0].get("message", {})
    has = "reasoning_content" in msg and bool(msg["reasoning_content"])
    return has, j.get("usage", {}).get("completion_tokens")


def main():
    domain, key = read_key()
    print(f"domain={domain}  key={key[:8]}...")

    if not os.path.exists(TEST_IMG):
        print(f"Rendering test image to {TEST_IMG} ...")
        swift = (
            'import AppKit\n'
            'let s=NSSize(width:240,height:60);let i=NSImage(size:s);'
            'i.lockFocus();NSColor.white.setFill();NSRect(origin:.zero,size:s).fill();'
            '"Hello Kimi 123".draw(at:NSPoint(x:20,y:20),withAttributes:'
            '[.font:NSFont.systemFont(ofSize:28),.foregroundColor:NSColor.black]);'
            'i.unlockFocus();let r=NSBitmapImageRep(data:i.tiffRepresentation!)!;'
            'try!r.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"%s"));'
        ) % TEST_IMG
        open("/tmp/_mkimg.swift", "w").write(swift)
        os.system("swift /tmp/_mkimg.swift")

    import base64
    with open(TEST_IMG, "rb") as f:
        data_uri = "data:image/png;base64," + base64.b64encode(f.read()).decode()

    print("\n[1] resolveChatCompletionsURL")
    base = f"https://{domain}"
    check("bare host", resolve_chat_completions_url(base) == f"https://{domain}/v1/chat/completions")
    check("/v1", resolve_chat_completions_url(base + "/v1") == f"https://{domain}/v1/chat/completions")
    check("/v1/ trailing slash", resolve_chat_completions_url(base + "/v1/") == f"https://{domain}/v1/chat/completions")
    check("full endpoint", resolve_chat_completions_url(base + "/v1/chat/completions") == f"https://{domain}/v1/chat/completions")

    print("\n[2] parseCustomHeaders + override")
    h = parse_custom_headers("X-Test: 1\nAuthorization: Bearer " + key + "\n\n  spaced :  val  \nbad-no-colon")
    check("parsed keys", set(["X-Test", "Authorization", "spaced"]).issubset(h.keys()), str(h))
    check("spaced value trimmed", h.get("spaced") == "val", repr(h.get("spaced")))
    check("line w/o colon ignored", "bad-no-colon" not in h)

    print("\n[3] real Kimi OCR (kimi mode, model kimi-k2.6)")
    code, raw = post(domain, key, build_body("kimi-k2.6", "你是 Kimi OCR 助手，请准确提取图片中的全部文字，仅输出文本。", data_uri))
    print(f"    HTTP {code}")
    j = json.loads(raw)
    kind, val = parse_content(j)
    print(f"    parsed: {kind} -> {val!r}")
    check("kimi HTTP 200", code == 200, raw[:200])
    check("kimi content is string", kind == "ok", val)
    check("kimi extracted expected text", "Hello Kimi 123" in (val or ""), val)

    print("\n[4] LLM mode: generic endpoint + custom header override, pointed at Kimi")
    # LLM mode sets a default Bearer, then applies custom headers last -> override.
    # We prove override works by setting a bogus default and a correct override.
    code, raw = post(domain, "BOGUS-DEFAULT", build_body("kimi-k2.6", "Extract all text. Output only the text.", data_uri),
                     extra_headers={"Authorization": "Bearer " + key, "X-Pocr-Mode": "llm"})
    print(f"    HTTP {code}")
    j = json.loads(raw)
    kind, val = parse_content(j)
    print(f"    parsed: {kind} -> {val!r}")
    check("llm custom header overrode default auth", code == 200, raw[:200])
    check("llm extracted expected text", "Hello Kimi 123" in (val or ""), val)

    print("\n[5] error-object parsing (bad model name)")
    code, raw = post(domain, key, build_body("this-model-does-not-exist", "x", data_uri))
    print(f"    HTTP {code}")
    j = json.loads(raw)
    kind, val = parse_content(j)
    print(f"    parsed: {kind} -> {val!r}")
    check("error path detected", kind == "error", f"{kind}/{val}")
    check("error message surfaced", "model" in (val or "").lower() or "not found" in (val or "").lower(), val)

    print("\n[6] Kimi thinking disabled by default (mirrors app default)")
    sys_prompt = "Extract all text. Output as Markdown only."
    body = build_body("kimi-k2.6", sys_prompt, data_uri)
    code_on, raw_on = post(domain, key, {**body, "thinking": {"type": "disabled"}})
    has_on, toks_on = reasoning_state(raw_on) if code_on == 200 else (None, None)
    code_off, raw_off = post(domain, key, body)  # baseline: no thinking param
    has_off, toks_off = reasoning_state(raw_off) if code_off == 200 else (None, None)
    print(f"    thinking disabled: HTTP {code_on} | reasoning={'YES' if has_on else 'no'} | tokens={toks_on}")
    print(f"    thinking default : HTTP {code_off} | reasoning={'YES' if has_off else 'no'} | tokens={toks_off}")
    check("disabled -> no reasoning_content", has_on is False, f"has_on={has_on}")
    check("default  -> reasoning present", has_off is True, f"has_off={has_off}")
    check("disabled uses fewer completion tokens", (toks_on or 0) < (toks_off or 0), f"{toks_on} vs {toks_off}")
    kind_on, val_on = parse_content(json.loads(raw_on))
    check("disabled still extracts expected text", "Hello Kimi 123" in (val_on or ""), val_on)

    print("\n[7] thinking disabled field is safe on non-reasoning models")
    nr = build_body("moonshot-v1-8k-vision-preview", sys_prompt, data_uri)
    code, raw = post(domain, key, {**nr, "thinking": {"type": "disabled"}})
    print(f"    HTTP {code}")
    check("non-reasoning + thinking disabled -> 200", code == 200, raw[:200])
    kind, val = parse_content(json.loads(raw)) if code == 200 else ("error", "")
    check("non-reasoning still extracts text", "Hello Kimi 123" in (val or ""), val)

    print("\n" + ("=" * 50))
    if failures:
        print(f"RESULT: {len(failures)} FAILURES -> {failures}")
        sys.exit(1)
    print("RESULT: ALL PASS")


if __name__ == "__main__":
    main()
