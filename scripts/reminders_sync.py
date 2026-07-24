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
    for calendar in principal.calendars():
        supported = calendar.get_supported_components()
        if "VTODO" in supported:
            return calendar
    raise RuntimeError("没有找到支持 VTODO（提醒事项）的列表")


def create_test_reminder(reminders_list: caldav.Calendar) -> None:
    due = datetime.now(timezone.utc) + timedelta(hours=1)
    reminders_list.save_todo(
        summary="HealthExporter Reminders 集成测试",
        due=due,
    )


def main() -> None:
    apple_id = os.environ["APPLE_ID"]
    app_password = os.environ["APPLE_APP_PASSWORD"]

    client = caldav.DAVClient(url=CALDAV_URL, username=apple_id, password=app_password)
    principal = client.principal()

    reminders_list = find_reminders_list(principal)
    print(f"找到提醒事项列表: {reminders_list.name}")

    create_test_reminder(reminders_list)
    print("测试提醒事项创建成功")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"失败: {exc}", file=sys.stderr)
        sys.exit(1)
