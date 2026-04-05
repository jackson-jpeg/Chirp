#!/usr/bin/env python3
"""
Enhance App Store screenshot scaffolds using Gemini's image editing API.
Takes a scaffold image and a prompt, returns an enhanced version.
"""

import argparse
import base64
import json
import os
import sys
import urllib.request
import urllib.error

API_KEY = os.environ.get("GEMINI_API_KEY", "")
MODEL = "gemini-2.5-flash-image"


def encode_image(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def enhance(scaffold_path, prompt, output_path, style_ref_path=None):
    if not API_KEY:
        print("Error: GEMINI_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    parts = []

    # Add prompt text
    parts.append({"text": prompt})

    # Add scaffold image
    scaffold_b64 = encode_image(scaffold_path)
    parts.append({
        "inlineData": {
            "mimeType": "image/png",
            "data": scaffold_b64
        }
    })

    # Add style reference if provided
    if style_ref_path and os.path.exists(style_ref_path):
        ref_b64 = encode_image(style_ref_path)
        parts.append({
            "inlineData": {
                "mimeType": "image/jpeg" if style_ref_path.endswith(".jpg") else "image/png",
                "data": ref_b64
            }
        })

    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"]
        }
    }

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={API_KEY}"

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"API error {e.code}: {body}", file=sys.stderr)
        sys.exit(1)

    # Extract image from response
    candidates = result.get("candidates", [])
    for candidate in candidates:
        parts = candidate.get("content", {}).get("parts", [])
        for part in parts:
            if "inlineData" in part:
                img_data = base64.b64decode(part["inlineData"]["data"])
                with open(output_path, "wb") as f:
                    f.write(img_data)
                print(f"Saved: {output_path}")
                return True
            elif "text" in part:
                print(f"Text response: {part['text'][:200]}", file=sys.stderr)

    print("No image in response", file=sys.stderr)
    return False


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--scaffold", required=True, help="Path to scaffold PNG")
    p.add_argument("--prompt", required=True, help="Enhancement prompt")
    p.add_argument("--output", required=True, help="Output path")
    p.add_argument("--style-ref", help="Style reference image (first approved screenshot)")
    args = p.parse_args()

    enhance(args.scaffold, args.prompt, args.output, args.style_ref)


if __name__ == "__main__":
    main()
