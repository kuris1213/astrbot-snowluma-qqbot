"""从一份真实 AstrBot 配置生成脱敏模板（维护者工具，部署时不需要运行）。

输入目录由环境变量 ``ASTRBOT_SRC`` 指定（指向某个 AstrBot 的 data 目录）。
输出到仓库的 ``templates/astrbot``。

    set ASTRBOT_SRC=D:\\your\\astrbot\\data
    python scripts\\build_templates.py

注意：它会读取真实配置（含 Key / Cookie），但只把脱敏后的结构写进模板。
运行前请确认输出目录里没有要保留的手工修改。
"""

from __future__ import annotations

import json
import os

SRC = os.environ.get("ASTRBOT_SRC", "")
if not SRC:
    raise SystemExit("请先设置 ASTRBOT_SRC，例如：set ASTRBOT_SRC=D:\\your\\astrbot\\data")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "templates", "astrbot")
PLUGINS = [
    "astrbot_plugin_meme_manager",
    "astrbot_plugin_proactive_chat",
    "astrbot_plugin_bilibili_ai_bot",
    "astrbot_plugin_ja_voice",
    "astrbot_plugin_qzone_ultra",
    "astrbot_plugin_memewiki",
    "astrbot_plugin_suanle_bushuo",
    "astrbot_plugin_hotsearch",
    "astrbot_plugin_mailer",
    "astrbot_plugin_zhen_deepseek_web",
]

PLACEHOLDER_QQ = "YOUR_QQ_NUMBER"
PLACEHOLDER_UMO = "snowluma:FriendMessage:YOUR_QQ_NUMBER"


def load(path: str) -> dict:
    with open(path, encoding="utf-8-sig") as fh:
        return json.load(fh)


def dump(path: str, data: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def sanitize_cmd_config(d: dict) -> dict:
    for src in d.get("provider_sources", []):
        if src.get("provider") == "deepseek":
            src["key"] = ["sk-REPLACE_WITH_YOUR_DEEPSEEK_KEY"]
    for prov in d.get("provider", []):
        if prov.get("id") == "aniflive_tts":
            prov["api_key"] = "sk-local"
    dash = d.setdefault("dashboard", {})
    dash["password"] = ""
    dash["pbkdf2_password"] = ""
    dash["jwt_secret"] = ""
    dash["password_change_required"] = True
    d["admins_id"] = [PLACEHOLDER_QQ]
    for plat in d.get("platform", []):
        if plat.get("type") == "aiocqhttp":
            plat["ws_reverse_token"] = "REPLACE_WITH_RANDOM_ONEBOT_TOKEN"
    # 清掉与个人账号绑定的联网搜索 key（原本就是空数组，显式写空更直观）
    ps = d.setdefault("provider_settings", {})
    for k in list(ps):
        if k.startswith("websearch_") and k.endswith("_key"):
            ps[k] = []
    return d


def sanitize_plugin(name: str, d: dict) -> dict:
    if name == "astrbot_plugin_bilibili_ai_bot":
        for k in ("SESSDATA", "BILI_JCT", "REFRESH_TOKEN", "BUVID3", "BUVID4"):
            if k in d:
                d[k] = ""
        d["DEDE_USER_ID"] = ""
        d["OWNER_MID"] = ""
        d["OWNER_NAME"] = "主人"
        d["OWNER_BILI_NAME"] = ""
        for k in ("OWNER_QQ_UMO", "WEEKLY_SUMMARY_QQ_UMO", "ABUSE_ALERT_QQ_UMO", "DAILY_SUMMARY_QQ_UMO"):
            if k in d:
                d[k] = PLACEHOLDER_UMO
    elif name == "astrbot_plugin_proactive_chat":
        for block in ("friend_settings", "group_settings"):
            if block in d and d[block].get("session_list"):
                d[block]["session_list"] = [PLACEHOLDER_UMO]
        d.setdefault("web_admin", {})["password"] = ""
    elif name == "astrbot_plugin_qzone_ultra":
        if "admin_uins" in d:
            d["admin_uins"] = PLACEHOLDER_QQ
        d["cookies_str"] = ""
    elif name == "astrbot_plugin_suanle_bushuo":
        if d.get("must_reply_umo"):
            d["must_reply_umo"] = [PLACEHOLDER_QQ]
    elif name == "astrbot_plugin_ja_voice":
        d["block_shell_tools"] = False
    return d


def main() -> None:
    cmd = sanitize_cmd_config(load(os.path.join(SRC, "cmd_config.json")))
    dump(os.path.join(OUT, "cmd_config.json"), cmd)
    for name in PLUGINS:
        path = os.path.join(SRC, "config", f"{name}_config.json")
        if not os.path.exists(path):
            print("skip missing", name)
            continue
        data = sanitize_plugin(name, load(path))
        dump(os.path.join(OUT, "plugins", f"{name}_config.json"), data)
        print("wrote", name)


if __name__ == "__main__":
    main()
