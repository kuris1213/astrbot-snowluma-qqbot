"""打印 AstrBot 知识库数据库中所有 kb_id（每行一个）。

用法：python kb_list_ids.py <kb.db 路径>
供 start-astrbot.ps1 清理孤立知识库目录时使用。
"""

import sqlite3
import sys


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    try:
        con = sqlite3.connect(sys.argv[1])
        rows = con.execute("select kb_id from knowledge_bases").fetchall()
        con.close()
    except Exception as exc:  # noqa: BLE001
        print(f"error: {exc}", file=sys.stderr)
        return 1
    for (kb_id,) in rows:
        if kb_id:
            print(kb_id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
