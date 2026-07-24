"""连接 iCloud CalDAV，把训练计划写进 Reminders。

现在这一版只做最小验证：找到一个支持 VTODO 的列表，创建一条测试提醒事项。
等训练计划本身的数据结构定下来后，再把 create_test_reminder 换成读取
真实计划内容、按天生成多条待办项的逻辑。
"""

import os
import sys
from datetime import datetime, timedelta, timezone

import caldav

CALDAV_URL = "https://caldav.icloud.com/"


def find_reminders_list(principal: caldav.Principal) -> caldav.Calendar:
    print("--- 账号里所有日历/列表 ---")
    candidates = []
    for calendar in principal.calendars():
        supported = set(calendar.get_supported_components())
        print(f"名字: {calendar.get_display_name()!r}, 支持类型: {supported}")
        if supported == {"VTODO"}:
            candidates.append(calendar)

    if not candidates:
        raise RuntimeError("没有找到「只支持 VTODO」的纯提醒事项列表（可能都是日历，兼带 VTODO）")
    if len(candidates) > 1:
        names = [c.get_display_name() for c in candidates]
        print(f"警告：找到多个候选列表 {names}，先用第一个")
    return candidates[0]


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

    client = caldav.DAVClient(url=CALDAV_URL, username=apple_id, password=app_password)
    principal = client.principal()

    reminders_list = find_reminders_list(principal)
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
