"""Entry point: python -m dragonfarm.publish --dir <dir> --repo <user/name> [--private] [--commit-message MSG]

Pushes a folder (a merged model or a LoRA adapter) to the Hugging Face
Hub, creating the repo first if it does not exist yet.
"""

import argparse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--commit-message", default=None)
    ap.add_argument("--private", action="store_true")
    a = ap.parse_args()

    from huggingface_hub import HfApi

    api = HfApi()
    api.create_repo(a.repo, repo_type="model", private=a.private, exist_ok=True)
    api.upload_folder(
        folder_path=a.dir,
        repo_id=a.repo,
        repo_type="model",
        commit_message=a.commit_message or "Upload from dragonfarm",
    )
    print(f"https://huggingface.co/{a.repo}")


if __name__ == "__main__":
    main()
