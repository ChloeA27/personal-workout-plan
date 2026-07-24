"""一次性本地脚本：走一遍 Google OAuth 授权，拿到 refresh token。

只需要在你自己的 Mac 上跑一次。会打开浏览器让你登录、同意授权，
授权成功后在终端打印出 refresh token，把它存进 GitHub Actions Secrets
（GOOGLE_REFRESH_TOKEN），然后这个脚本和它生成的任何本地文件都可以删掉。

用法:
    export GOOGLE_CLIENT_ID="你的 Client ID"
    export GOOGLE_CLIENT_SECRET="你的 Client Secret"
    python scripts/google_tasks_auth.py
"""

import os
import sys

from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ["https://www.googleapis.com/auth/tasks"]


def main() -> None:
    client_id = os.environ.get("GOOGLE_CLIENT_ID")
    client_secret = os.environ.get("GOOGLE_CLIENT_SECRET")
    if not client_id or not client_secret:
        print("请先 export GOOGLE_CLIENT_ID 和 GOOGLE_CLIENT_SECRET", file=sys.stderr)
        sys.exit(1)

    client_config = {
        "installed": {
            "client_id": client_id,
            "client_secret": client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"],
        }
    }

    flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
    # 这里会自动打开浏览器，你登录、同意授权后，浏览器会跳转回本地，
    # 脚本自动捕获授权结果，不需要你手动复制粘贴任何代码。
    credentials = flow.run_local_server(port=0)

    print("\n===== 授权成功 =====")
    print(f"Refresh token: {credentials.refresh_token}")
    print("\n把这个 refresh token 存进 GitHub Actions Secrets: GOOGLE_REFRESH_TOKEN")
    print("同时把 GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET 也存进去。")


if __name__ == "__main__":
    main()
