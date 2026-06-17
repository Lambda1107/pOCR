#!/usr/bin/env python3
"""Cloud API OCR using PaddleOCRClient Python SDK directly."""
import argparse
import json
import sys


def str2bool(v):
    return v.lower() in ("true", "yes", "t", "y", "1")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="Path to input image")
    parser.add_argument("--output", required=True, help="Path for result JSON")
    parser.add_argument("--token", required=True)
    parser.add_argument("--model", default="PaddleOCR-VL-1.6")
    parser.add_argument("--poll-timeout", type=int, default=120)
    parser.add_argument("--use-layout-detection", type=str2bool, default=True)
    parser.add_argument("--use-chart-recognition", type=str2bool, default=False)
    parser.add_argument("--prettify-markdown", type=str2bool, default=False)
    args = parser.parse_args()

    from paddleocr import PaddleOCRClient, PaddleOCRVLOptions

    options = PaddleOCRVLOptions(
        use_layout_detection=args.use_layout_detection,
        use_chart_recognition=args.use_chart_recognition,
        prettify_markdown=args.prettify_markdown,
    )

    client = PaddleOCRClient(
        token=args.token,
        poll_timeout=float(args.poll_timeout),
    )

    try:
        result = client.parse_document(
            file_path=args.image,
            model=args.model,
            options=options,
        )

        pages_data = []
        for page in result.pages:
            pages_data.append({
                "markdownText": page.markdown_text,
                "markdownImages": page.markdown_images,
                "outputImages": page.output_images,
            })

        with open(args.output, "w") as f:
            json.dump({"pages": pages_data, "job_id": result.job_id}, f)

        print(json.dumps({"status": "ok"}))
    finally:
        client.close()


if __name__ == "__main__":
    main()
