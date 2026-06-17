#!/usr/bin/env python3
"""Local OCR using PaddleOCRVL Python API directly."""
import argparse
import json
import sys
from pathlib import Path


def str2bool(v):
    return v.lower() in ("true", "yes", "t", "y", "1")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="Path to input image")
    parser.add_argument("--output-dir", required=True, help="Directory for result JSON")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--pipeline-version", default="v1.6")
    parser.add_argument("--use-layout-detection", type=str2bool, default=True)
    parser.add_argument("--use-chart-recognition", type=str2bool, default=False)
    parser.add_argument("--format-block-content", type=str2bool, default=False)
    parser.add_argument("--use-doc-orientation-classify", type=str2bool, default=False)
    parser.add_argument("--use-doc-unwarping", type=str2bool, default=False)
    args = parser.parse_args()

    from paddleocr import PaddleOCRVL

    pipeline = PaddleOCRVL(
        device=args.device,
        pipeline_version=args.pipeline_version,
        use_layout_detection=args.use_layout_detection,
        use_chart_recognition=args.use_chart_recognition,
        format_block_content=args.format_block_content,
        use_doc_orientation_classify=args.use_doc_orientation_classify,
        use_doc_unwarping=args.use_doc_unwarping,
    )

    try:
        output = pipeline.predict(args.image)
        for res in output:
            res.save_to_json(save_path=args.output_dir)
        print(json.dumps({"status": "ok"}))
    finally:
        pipeline.close()


if __name__ == "__main__":
    main()
