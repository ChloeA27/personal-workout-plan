"""连接 Google Tasks API，把训练计划写进去。

现在这一版只做最小验证：找到/创建一个任务列表，创建一条测试任务。
等训练计划本身的数据结构定下来后，再把 create_test_task 换成读取
真实计划内容、按天生成多条任务的逻辑。
"""

import os
import sys
from datetime import datetime, timedelta, timezone

import requests

TOKEN_URL = "https://oauth2.googleapis.com/token"
TASKS_API_BASE = "https://tasks.googleapis.com/tasks/v1"
DEFAULT_LIST_NAME = "健身计划"


def get_access_token(client_id: str, client_secret: str, refresh_token: str) -> str:
    response = requests.post(
        TOKEN_URL,
        data={
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
    )
    response.raise_for_status()
    return response.json()["access_token"]


def find_or_create_tasklist(access_token: str, list_name: str) -> str:
    headers = {"Authorization": f"Bearer {access_token}"}

    response = requests.get(f"{TASKS_API_BASE}/users/@me/lists", headers=headers)
    response.raise_for_status()
    existing_lists = response.json().get("items", [])

    print("--- 账号里现有的任务列表 ---")
    for tasklist in existing_lists:
        print(f"名字: {tasklist['title']!r}, id: {tasklist['id']}")
        if tasklist["title"] == list_name:
            return tasklist["id"]

    print(f"没找到 {list_name!r}，创建一个新的")
    response = requests.post(
        f"{TASKS_API_BASE}/users/@me/lists",
        headers=headers,
        json={"title": list_name},
    )
    response.raise_for_status()
    return response.json()["id"]


def create_test_task(access_token: str, tasklist_id: str) -> str:
    headers = {"Authorization": f"Bearer {access_token}"}
    due = (datetime.now(timezone.utc) + timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%S.000Z")

    response = requests.post(
        f"{TASKS_API_BASE}/lists/{tasklist_id}/tasks",
        headers=headers,
        json={
            "title": "workout-plan Google Tasks 集成测试",
            "due": due,
        },
    )
    response.raise_for_status()
    return response.json()["id"]


def main() -> None:
    client_id = os.environ["GOOGLE_CLIENT_ID"]
    client_secret = os.environ["GOOGLE_CLIENT_SECRET"]
    refresh_token = os.environ["GOOGLE_REFRESH_TOKEN"]
    list_name = os.environ.get("GOOGLE_TASKLIST_NAME") or DEFAULT_LIST_NAME

    access_token = get_access_token(client_id, client_secret, refresh_token)

    tasklist_id = find_or_create_tasklist(access_token, list_name)
    print(f"使用任务列表: {list_name!r} (id={tasklist_id})")

    task_id = create_test_task(access_token, tasklist_id)
    print(f"测试任务创建成功, id={task_id}")

    headers = {"Authorization": f"Bearer {access_token}"}
    response = requests.get(f"{TASKS_API_BASE}/lists/{tasklist_id}/tasks", headers=headers)
    response.raise_for_status()
    tasks = response.json().get("items", [])
    print(f"这个列表里现在一共有 {len(tasks)} 条任务")
    for task in tasks:
        print(f"- {task['title']} (完成状态: {task.get('status')})")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"失败: {exc}", file=sys.stderr)
        sys.exit(1)
