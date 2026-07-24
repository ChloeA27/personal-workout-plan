"""连接 iCloud CalDAV，把训练计划写进 Reminders。

现在这一版只做最小验证：找到一个支持 VTODO 的列表，创建一条测试提醒事项。
等训练计划本身的数据结构定下来后，再把 create_test_reminder 换成读取
真实计划内容、按天生成多条待办项的逻辑。
"""

import os
import sys
import time
from datetime import datetime, timedelta, timezone

import caldav

CALDAV_URL = "https://caldav.icloud.com/"
DEFAULT_LIST_NAME = "workout-plan"
DISCOVERY_ATTEMPTS = 6
DISCOVERY_RETRY_SECONDS = 8


def find_reminders_list(principal: caldav.Principal, list_name: str) -> caldav.Calendar:
    """iCloud 的 CalDAV 日历枚举偶尔会漏掉一部分（同一账号连续两次请求
    结果都不完整、缺的东西还不一样），所以在一次运行里多试几次，而不是
    只信一次 principal.calendars() 的结果。"""
    all_names: list[str] = []
    for attempt in range(1, DISCOVERY_ATTEMPTS + 1):
        print(f"--- 第 {attempt} 次尝试列出账号里所有日历/列表 ---")
        all_names = []
        for calendar in principal.calendars():
            supported = set(calendar.get_supported_components())
            name = calendar.get_display_name()
            print(f"名字: {name!r}, 支持类型: {supported}")
            all_names.append(name)
            if name == list_name and supported == {"VTODO"}:
                return calendar
        if attempt < DISCOVERY_ATTEMPTS:
            print(f"这次没找到，{DISCOVERY_RETRY_SECONDS} 秒后重试...")
            time.sleep(DISCOVERY_RETRY_SECONDS)

    raise RuntimeError(
        f"重试 {DISCOVERY_ATTEMPTS} 次后，仍没有找到名字精确匹配 {list_name!r} 且只支持 VTODO 的列表。"
        f"最后一次看到的列表: {all_names}"
    )


def create_test_reminder(reminders_list: caldav.Calendar) -> str:
    due = datetime.now(timezone.utc) + timedelta(hours=1)
    todo = reminders_list.save_todo(
        summary="HealthExporter Reminders 集成测试",
        due=due,
    )
    return todo.id


def main() -> None:
    apple_id = os.environ["APPLE_ID"]
    app_password = os.environ["APPLE_APP_PASSWORD"]
    list_name = os.environ.get("REMINDERS_LIST_NAME") or DEFAULT_LIST_NAME

    client = caldav.DAVClient(url=CALDAV_URL, username=apple_id, password=app_password)
    principal = client.principal()

    reminders_list = find_reminders_list(principal, list_name)
    print(f"找到提醒事项列表: {reminders_list.get_display_name()}")

    new_uid = create_test_reminder(reminders_list)
    print(f"测试提醒事项创建成功, uid={new_uid}")

    print("--- 回头查一次这个列表里的所有待办 ---")
    all_todos = reminders_list.todos(include_completed=True)
    print(f"这个列表里现在一共有 {len(all_todos)} 条待办")
    for todo in all_todos:
        print("=" * 40)
        print(todo.data)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"失败: {exc}", file=sys.stderr)
        sys.exit(1)
